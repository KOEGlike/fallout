# Issues one ship_review koi transaction per non-trial kept project member when a
# DESIGN ship reaches :approved. Koi is split per-contribution — proportional to each
# member's attributed seconds this cycle, the same per-entry attribution used for
# user-facing hours; the owner absorbs any integer remainder. A member who logged no
# contribution this cycle gets 0 and no ledger row. Build ships award gold via
# ShipGoldAwarder instead (DR → koi, BR → gold).
#
# Single source of truth for the koi formula. Called from Ship#award_ship_review_currency!
# (after_update_commit) and from `rake koi:reconcile_ship_reviews` (operator-triggered
# backfill / safety-net). Idempotent per member — the partial unique index on
# koi_transactions(ship_id, user_id) WHERE reason = 'ship_review' is the guarantee.
#
# Returns an array of Results, one per eligible member, each tagged with one of:
#   :created                  — new KoiTransaction was inserted
#   :skipped_already_awarded  — DB unique index rejected the insert (race or replay)
#   :skipped_zero_amount      — hours+adjustments sum to 0; nothing to record
#   :skipped_trial_user       — all eligible members are trial users
#   :skipped_not_approved     — ship status is not :approved
#   :skipped_wrong_ship_type  — ship is not a design ship (koi is DR-only)
class ShipKoiAwarder
  Result = Data.define(:status, :transaction, :amount)

  RATE_KOI_PER_HOUR = 7

  def self.call(ship)
    return [ Result.new(status: :skipped_not_approved,    transaction: nil, amount: 0) ] unless ship.approved?
    return [ Result.new(status: :skipped_wrong_ship_type, transaction: nil, amount: 0) ] unless ship.ship_type_design?

    members = eligible_members(ship)
    return [ Result.new(status: :skipped_trial_user, transaction: nil, amount: 0) ] if members.empty?

    total = compute_amount(ship)
    return [ Result.new(status: :skipped_zero_amount, transaction: nil, amount: 0) ] if total.zero?

    shares = compute_shares(total, members, ship.project.user_id, member_weights(ship, members))

    members.filter_map do |member|
      amount = shares[member.id]
      next if amount.zero? # per-entry split: a member with no logged contribution this cycle gets 0 — no row (amount must be non-zero)
      desc = build_description(ship, amount, total, members.size)
      txn = KoiTransaction.create!(
        user: member,
        ship: ship,
        actor: nil,
        amount: amount,
        reason: "ship_review",
        description: desc
      )
      Result.new(status: :created, transaction: txn, amount: amount)
    rescue ActiveRecord::RecordNotUnique
      Result.new(status: :skipped_already_awarded, transaction: nil, amount: 0)
    end
  end

  # Public so the rake task / dry-run preview can show the would-be amount without inserting.
  #
  # Invariant: ship.approved_public_seconds is per-cycle by construction. It mirrors
  # time_audit_review.approved_public_seconds, which both the TA frontend
  # (pages/admin/reviews/time_audits/show.tsx) and the auto-approval path
  # (Ship#compute_approved_public_seconds via #carry_forward_ta_annotations!) compute
  # from ship.new_journal_entries — entries created strictly after
  # previous_approved_ship.created_at. So summing per-ship gives the correct
  # lifetime total without subtracting prior cycles. DO NOT swap to ship.total_hours
  # or any project-wide aggregator — those count the full history.
  def self.compute_amount(ship)
    seconds = ship.approved_public_seconds.to_i # Public/user-facing hours only — internal hours_adjustment is excluded by design
    hours_koi = Rational(seconds * RATE_KOI_PER_HOUR, 3600).round
    adjustment = ship.design_review&.koi_adjustment.to_i # DR-only; BR adjusts gold via ShipGoldAwarder
    hours_koi + adjustment
  end

  def self.eligible_members(ship)
    owner = ship.project.user
    # Use the preloaded association when available (avoids N+1 in batch contexts).
    collab_users = ship.project.collaborators.map(&:user)
    ([ owner ] + collab_users).uniq { |u| u.id }.reject { |u| u.trial? || u.discarded? }
  end

  # Per-member attributed seconds across this ship's cycle journal entries, using the same
  # per-entry attribution as user-facing hours (author + kept journal collaborators share
  # each entry's seconds equally). Drives the proportional split in compute_shares.
  def self.member_weights(ship, members)
    je_ids = ship.new_journal_entries.ids
    members.to_h { |u| [ u.id, JournalEntry.batch_user_attributed_seconds(je_ids, u).values.sum ] }
  end

  # Distributes total proportionally to each member's contributed seconds this cycle
  # (weights), mirroring how user-facing hours are attributed per journal entry. The owner
  # absorbs the integer rounding remainder so shares always sum to total exactly. Falls back
  # to an even split only when no member has any attributed seconds (e.g. an adjustment-only
  # award with no logged hours). Recipient falls back to the first member if the owner is not
  # eligible (e.g. trial user).
  def self.compute_shares(total, members, owner_id, weights)
    recipient_id = members.find { |u| u.id == owner_id }&.id || members.first.id
    total_weight = members.sum { |u| weights[u.id].to_i }
    shares =
      if total_weight.positive?
        members.to_h { |u| [ u.id, total * weights[u.id].to_i / total_weight ] }
      else
        base = total / members.size
        members.to_h { |u| [ u.id, base ] }
      end
    shares[recipient_id] += total - shares.values.sum
    shares
  end

  def self.build_description(ship, amount, total, member_count)
    seconds = ship.approved_public_seconds.to_i
    hours = (seconds / 3600.0).round(2)
    base_koi = Rational(seconds * RATE_KOI_PER_HOUR, 3600).round
    description = "Ship ##{ship.id} approved — #{hours} hrs × #{RATE_KOI_PER_HOUR} koi"
    if total != base_koi
      adjustment = total - base_koi
      sign = adjustment >= 0 ? "+" : "−"
      description += " #{sign} #{adjustment.abs} koi review adjustment"
    end
    description += " = #{total} total split by hours across #{member_count} members (your share: #{amount})" if member_count > 1
    description
  end
end
