# Repairs Active Storage signed_ids that were minted while the new web/worker
# servers were running with SECRET_KEY_BASE=CHANGEME (cutover at 2026-05-05
# 12:00 ET / 16:00 UTC). Once the env var is removed and Rails falls back to
# Rails.application.credentials.secret_key_base, any signed_id minted during the
# CHANGEME window no longer verifies and the corresponding blob URL 404s.
#
# Run AFTER the env var has been removed and the new server is back on the
# credentials-derived secret_key_base.
#
# Usage:
#   bin/rails signed_id_repair:probe
#   bin/rails 'signed_id_repair:journal_entries[true]'   # dry-run (default)
#   bin/rails 'signed_id_repair:journal_entries[false]'  # write changes
#   bin/rails signed_id_repair:clear_html_cache
namespace :signed_id_repair do
  WINDOW_START = Time.utc(2026, 5, 5, 16, 0).freeze # 2026-05-05 12:00 ET
  CHANGEME_VALUE = "CHANGEME"
  AS_URL_PATTERN = %r{/user-attachments/blobs/(?:redirect/|proxy/)?([^)\s"'<>/]+)}

  # Live verifier — uses whatever Rails.application.secret_key_base resolves to right now.
  def correct_verifier
    @correct_verifier ||= Rails.application.message_verifier("ActiveStorage")
  end

  # Replicates how Rails builds message_verifier("ActiveStorage"): KeyGenerator with
  # iterations=1000 + 64-byte derived key, SHA1 digest, JSON serializer. Verified
  # by inspection against ActiveStorage::Blob.signed_id_verifier on this codebase.
  def changeme_verifier
    @changeme_verifier ||= ActiveSupport::MessageVerifier.new(
      ActiveSupport::KeyGenerator.new(CHANGEME_VALUE, iterations: 1000).generate_key("ActiveStorage", 64),
      digest: "SHA1",
      serializer: JSON
    )
  end

  desc "Sanity-check both verifiers round-trip correctly"
  task probe: :environment do
    blob = ActiveStorage::Blob.first or abort("No blobs to probe with.")

    real_sid = blob.signed_id
    fake_sid = changeme_verifier.generate(blob.id, purpose: :blob_id)

    puts "secret_key_base[0,12]: #{Rails.application.secret_key_base[0, 12]}"
    puts "Expected (credentials): #{Rails.application.credentials.secret_key_base[0, 12]}"
    puts
    puts "Real (current-key) sid -> correct verifier: #{correct_verifier.verified(real_sid, purpose: :blob_id).inspect}"
    puts "Real (current-key) sid -> changeme verifier: #{changeme_verifier.verified(real_sid, purpose: :blob_id).inspect}"
    puts "Fake (CHANGEME) sid    -> correct verifier: #{correct_verifier.verified(fake_sid, purpose: :blob_id).inspect}"
    puts "Fake (CHANGEME) sid    -> changeme verifier: #{changeme_verifier.verified(fake_sid, purpose: :blob_id).inspect}"
    puts
    puts "Expected: real verifies on correct only, fake verifies on changeme only."
  end

  desc "Repair signed_ids embedded in journal_entries.content during the CHANGEME window. Pass false to write."
  task :journal_entries, [ :dry_run ] => :environment do |_t, args|
    dry_run = args.fetch(:dry_run, "true").to_s != "false"
    puts "Mode: #{dry_run ? 'DRY-RUN' : 'EXECUTE'}"
    puts "Window: updated_at >= #{WINDOW_START.iso8601}"
    puts "Current secret_key_base[0,12]: #{Rails.application.secret_key_base[0, 12]}"

    if Rails.application.secret_key_base == CHANGEME_VALUE
      abort("Refusing to run: secret_key_base is still CHANGEME. Remove the env var and restart first.")
    end

    stats = Hash.new(0)

    JournalEntry.unscoped.where("updated_at >= ?", WINDOW_START).find_each do |je|
      stats[:rows_seen] += 1
      content = je.content.to_s
      next if content.empty?

      sids = content.scan(AS_URL_PATTERN).flatten.map { |s| Rack::Utils.unescape_path(s) }.uniq
      next if sids.empty?

      stats[:rows_with_sids] += 1
      stats[:sids_total] += sids.size
      replacements = {}

      sids.each do |sid|
        if correct_verifier.verified(sid, purpose: :blob_id)
          stats[:sids_already_correct] += 1
        elsif (blob_id = changeme_verifier.verified(sid, purpose: :blob_id))
          stats[:sids_changeme] += 1
          blob = ActiveStorage::Blob.find_by(id: blob_id)
          if blob
            replacements[sid] = correct_verifier.generate(blob.id, purpose: :blob_id)
          else
            stats[:sids_blob_missing] += 1
            warn "  [je=#{je.id}] CHANGEME sid points at blob_id=#{blob_id} but blob row is gone"
          end
        else
          stats[:sids_unverifiable] += 1
          warn "  [je=#{je.id}] sid verifies under neither key (probably never valid): #{sid[0, 40]}..."
        end
      end

      next if replacements.empty?

      new_content = content.dup
      replacements.each { |old_sid, new_sid| new_content.gsub!(old_sid, new_sid) }

      if dry_run
        puts "  [je=#{je.id}] would rewrite #{replacements.size} sid(s)"
      else
        # update! bumps updated_at on purpose: cache_key_with_version changes,
        # which auto-invalidates the rendered-markdown HTML cache for this entry.
        je.update!(content: new_content)
        stats[:rows_rewritten] += 1
        puts "  [je=#{je.id}] rewrote #{replacements.size} sid(s)"
      end
    end

    puts
    puts "Stats:"
    stats.sort.each { |k, v| puts "  #{k}: #{v}" }
  end

  desc "Clear cached rendered markdown so any stale CHANGEME URLs in cached HTML are dropped"
  task clear_html_cache: :environment do
    deleted = Rails.cache.delete_matched("*journal_entry_html_v1*")
    puts "delete_matched(*journal_entry_html_v1*) -> #{deleted.inspect}"
  end
end
