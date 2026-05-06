namespace :ships do
  desc <<~DESC
    Reconcile ship.approved_public_seconds against the current TimeAuditReview state.

    Default mode is dry-run — prints planned changes without writing.
    Pass APPLY=1 to actually update rows.

    Three drift cases handled:
      1. TA approved, ship value mismatches      → set ship.approved_public_seconds = ta.approved_public_seconds
      2. TA approved, ship value missing         → set ship.approved_public_seconds = ta.approved_public_seconds
      3. TA NOT approved (or no TA), ship value present → clear ship.approved_public_seconds (stale data from a prior approval that was later returned/cancelled)

    Only ship.approved_public_seconds is touched. KoiTransactions are unaffected
    (those are reconciled separately by koi:reconcile_ship_reviews).

    Examples:
      bin/rake ships:reconcile_approved_public_seconds
      bin/rake ships:reconcile_approved_public_seconds APPLY=1
  DESC
  task reconcile_approved_public_seconds: :environment do
    apply = ENV["APPLY"] == "1"

    mismatched = []
    stale      = []
    missing    = []

    Ship.includes(:time_audit_review).find_each do |ship|
      ta = ship.time_audit_review
      ta_value = (ta&.approved? ? ta.approved_public_seconds : nil)
      ship_value = ship.approved_public_seconds

      next if ta_value == ship_value

      bucket = if ta_value && ship_value && ta_value != ship_value
        :mismatched
      elsif ta_value && ship_value.nil?
        :missing
      else
        :stale
      end

      row = {
        ship_id: ship.id,
        ship_status: ship.status,
        ta_status: ta&.status,
        ship_value: ship_value,
        ta_value: ta_value
      }

      case bucket
      when :mismatched then mismatched << row
      when :missing    then missing << row
      when :stale      then stale << row
      end
    end

    mode = apply ? "APPLY" : "DRY RUN"
    puts "approved_public_seconds reconciliation — #{mode}"
    puts "=" * 50
    puts "Mismatched (TA approved, ship value differs): #{mismatched.size}"
    puts "Missing    (TA approved, ship value nil):    #{missing.size}"
    puts "Stale      (TA not approved, ship value set): #{stale.size}"
    puts ""

    show = ->(label, rows) do
      next if rows.empty?
      puts "#{label} (first 25):"
      rows.first(25).each do |r|
        puts "  ship_id=#{r[:ship_id]} ship_status=#{r[:ship_status]} ta_status=#{r[:ta_status].inspect} ship=#{r[:ship_value].inspect} ta=#{r[:ta_value].inspect}"
      end
      puts "  …(#{rows.size - 25} more)" if rows.size > 25
      puts ""
    end
    show.call("Mismatched", mismatched)
    show.call("Missing",    missing)
    show.call("Stale",      stale)

    unless apply
      puts "Dry run only — no rows updated. Re-run with APPLY=1 to write."
      next
    end

    puts "APPLYING — updating ships..."
    updated = 0
    (mismatched + missing).each do |r|
      Ship.where(id: r[:ship_id]).update_all(approved_public_seconds: r[:ta_value])
      updated += 1
    end
    stale.each do |r|
      Ship.where(id: r[:ship_id]).update_all(approved_public_seconds: nil)
      updated += 1
    end
    puts "Done. Updated #{updated} ships."
  end
end
