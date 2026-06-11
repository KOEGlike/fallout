namespace :lapse do
  desc "Backfill LapseTimelapse durations with actual video duration (via ffprobe)"
  task backfill_video_durations: :environment do
    total = LapseTimelapse.count
    updated = 0
    skipped = 0
    failed = 0

    LapseTimelapse.find_each.with_index do |lt, i|
      print "\r[#{i + 1}/#{total}] #{lt.name || lt.lapse_timelapse_id}..."

      unless lt.playback_url.present?
        skipped += 1
        next
      end

      output = `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 #{Shellwords.escape(lt.playback_url)} 2>&1`.strip
      video_duration = output.to_f

      if video_duration > 0
        real_duration = video_duration * 60 # 1 video second = 1 real minute
        old_duration = lt.duration
        lt.update!(duration: real_duration)
        updated += 1
        puts "\n  #{lt.name}: #{old_duration}s → #{real_duration}s (video: #{video_duration.round(1)}s)"
      else
        failed += 1
        puts "\n  Failed #{lt.name}: ffprobe returned '#{output}'"
      end
    rescue => e
      failed += 1
      puts "\n  Failed LapseTimelapse ##{lt.id}: #{e.message}"
    end

    puts "\nDone. Updated: #{updated}, Skipped: #{skipped}, Failed: #{failed}"
  end

  desc "Archive all LapseTimelapses (footage + metadata) to R2. FORCE=1 re-archives, INLINE=1 runs synchronously, LIMIT=n caps the batch"
  task archive_all: :environment do
    force = ENV["FORCE"] == "1"
    inline = ENV["INLINE"] == "1"
    limit = ENV["LIMIT"].presence&.to_i

    scope = force ? LapseTimelapse.all : LapseTimelapse.where(archived_at: nil)
    scope = scope.limit(limit) if limit
    total = scope.count

    # find_each ignores limit/order, so iterate the limited result set directly when capped.
    each_row = limit ? scope.each : scope.find_each

    unless inline
      each_row.each { |lt| ArchiveLapseTimelapseJob.perform_later(lt.id, force: force) }
      puts "Enqueued #{total} archive job(s) on the :heavy queue."
      next
    end

    archived = 0
    no_footage = [] # { id:, lapse_id:, note: } — Lapse has no video for these (flagged below)
    failures = []   # { id:, lapse_id:, error: } — real errors (flagged + logged below)

    each_row.with_index do |lt, i|
      print "\r[#{i + 1}/#{total}] #{lt.lapse_timelapse_id}...".ljust(60)
      begin
        case LapseArchiveService.new.archive!(lt, force: force)
        when :archived then archived += 1
        when :no_playback
          # Flag the journal link/duration so it's obvious which gaps actually back logged hours.
          rec = Recording.find_by(recordable_type: "LapseTimelapse", recordable_id: lt.id)
          note = "vis=#{lt.visibility} dur=#{lt.duration.to_i}s" \
                 "#{rec ? " journal=##{rec.journal_entry_id}" : " (unattached)"}"
          no_footage << { id: lt.id, lapse_id: lt.lapse_timelapse_id, note: note }
          puts "\n  ⚠️  No footage on Lapse — ##{lt.id} (#{lt.lapse_timelapse_id}) #{note}"
        end
      rescue => e
        failures << { id: lt.id, lapse_id: lt.lapse_timelapse_id, error: "#{e.class}: #{e.message}" }
        # Surface immediately and persist to the Rails log; the service already reported to Sentry.
        puts "\n  ❌  FAILED ##{lt.id} (#{lt.lapse_timelapse_id}): #{e.class}: #{e.message}"
        Rails.logger.error("[lapse:archive_all] FAILED ##{lt.id} (#{lt.lapse_timelapse_id}): #{e.class}: #{e.message}")
      end
    end

    puts "\n\nDone. Archived: #{archived}, No footage on Lapse: #{no_footage.size}, Failed: #{failed = failures.size} (of #{total})."

    write_report = lambda do |rows, label, filename|
      next if rows.empty?

      path = Rails.root.join("log", filename)
      File.open(path, "a") do |f|
        f.puts "# lapse:archive_all run @ #{Time.current.iso8601} — #{rows.size} #{label}"
        rows.each { |r| f.puts "##{r[:id]}\t#{r[:lapse_id]}\t#{r[:note] || r[:error]}" }
      end
      puts "\n#{label.capitalize} (also written to #{path}):"
      rows.each { |r| puts "  ##{r[:id]} #{r[:lapse_id]} — #{r[:note] || r[:error]}" }
    end

    write_report.call(no_footage, "no-footage timelapse(s)", "lapse_archive_no_footage.log")
    write_report.call(failures, "failure(s)", "lapse_archive_failures.log")
  end
end
