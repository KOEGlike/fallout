namespace :ships do
  desc <<~DESC
    Reconcile ship.approved_public_seconds against the ship's fully-approved status.

    Default mode is dry-run — prints planned changes without writing.
    Pass APPLY=1 to actually update rows.

    Invariant: ship.approved_public_seconds is non-nil ONLY when the ship is
    :approved AND its TA has an approved_public_seconds value. Any other state
    means the column should be nil.

    Two drift cases handled:
      1. Ship is :approved with a TA value, ship column missing/wrong → set to ta.approved_public_seconds
      2. Ship is NOT :approved (or missing TA), ship column present     → clear (nil)

    KoiTransactions are unaffected — those are reconciled separately by
    koi:reconcile_ship_reviews.

    Examples:
      bin/rake ships:reconcile_approved_public_seconds
      bin/rake ships:reconcile_approved_public_seconds APPLY=1
  DESC
  task reconcile_approved_public_seconds: :environment do
    apply = ENV["APPLY"] == "1"

    to_set   = []
    to_clear = []

    Ship.includes(:time_audit_review).find_each do |ship|
      ta = ship.time_audit_review
      target = if ship.approved? && ta&.approved? && ta.approved_public_seconds.present?
        ta.approved_public_seconds
      end

      next if ship.approved_public_seconds == target

      row = {
        ship_id: ship.id,
        ship_status: ship.status,
        ta_status: ta&.status,
        current: ship.approved_public_seconds,
        target: target
      }
      target.nil? ? (to_clear << row) : (to_set << row)
    end

    mode = apply ? "APPLY" : "DRY RUN"
    puts "approved_public_seconds reconciliation — #{mode}"
    puts "=" * 50
    puts "To set   (ship :approved, TA value, column missing/wrong): #{to_set.size}"
    puts "To clear (ship not fully approved, column present):       #{to_clear.size}"
    puts ""

    show = ->(label, rows) do
      next if rows.empty?
      puts "#{label} (first 25):"
      rows.first(25).each do |r|
        puts "  ship_id=#{r[:ship_id]} ship_status=#{r[:ship_status]} ta_status=#{r[:ta_status].inspect} current=#{r[:current].inspect} target=#{r[:target].inspect}"
      end
      puts "  …(#{rows.size - 25} more)" if rows.size > 25
      puts ""
    end
    show.call("Set",   to_set)
    show.call("Clear", to_clear)

    unless apply
      puts "Dry run only — no rows updated. Re-run with APPLY=1 to write."
      next
    end

    puts "APPLYING — updating ships..."
    updated = 0
    to_set.each do |r|
      Ship.where(id: r[:ship_id]).update_all(approved_public_seconds: r[:target])
      updated += 1
    end
    to_clear.each do |r|
      Ship.where(id: r[:ship_id]).update_all(approved_public_seconds: nil)
      updated += 1
    end
    puts "Done. Updated #{updated} ships."
  end
end
