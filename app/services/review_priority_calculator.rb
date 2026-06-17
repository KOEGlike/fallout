# Flags pending review ships whose collaborators are at/near the approval-hours qualification
# thresholds, so reviewers can prioritise them. A ship is "priority" when ANY one collaborator
# (owner or kept collaborator), evaluated independently, is not yet qualified (< PROJECTION_SECONDS
# approved) AND either:
#   (a) already has >= QUALIFY_SECONDS of approved public hours, or
#   (b) would cross PROJECTION_SECONDS once this ship's hours land — only when the Time Audit
#       has already approved (so the ship's eventual approved hours are known).
# Collaborators who have already qualified (>= PROJECTION_SECONDS) don't need a priority review.
#
# Approved hours are the live, per-user proportional total (matching User#approved_time_logged_seconds /
# HoursStatsCalculator). Computed in bulk for all ships at once — no per-row queries.
class ReviewPriorityCalculator
  QUALIFY_SECONDS = 50 * 3600
  PROJECTION_SECONDS = 60 * 3600
  # Added to a priority ship's real wait for queue-ordering math only — the actual wait is unchanged.
  WAIT_BOOST = 2.days

  def self.priority_ship_ids(ships)
    new(ships).priority_ship_ids
  end

  def initialize(ships)
    @ships = Array(ships).compact.uniq(&:id)
  end

  def priority_ship_ids
    return Set.new if @ships.empty?

    members = members_by_project(@ships.map(&:project_id).uniq)
    member_ids = members.values.flatten.uniq
    return Set.new if member_ids.empty?

    current = HoursStatsCalculator.public_approved_seconds_by_user(project_ids: attributable_project_ids(member_ids))
    projected = projected_increment_by_ship_user

    @ships.each_with_object(Set.new) do |ship, set|
      qualifies = (members[ship.project_id] || []).any? do |uid|
        seconds = current[uid].to_i
        next false if seconds >= PROJECTION_SECONDS # already qualified — no priority review needed
        next true if seconds >= QUALIFY_SECONDS
        added = projected.dig(ship.id, uid).to_i
        added.positive? && seconds + added >= PROJECTION_SECONDS
      end
      set << ship.id if qualifies
    end
  end

  private

  def members_by_project(project_ids)
    map = Hash.new { |h, k| h[k] = [] }
    Project.where(id: project_ids).pluck(:id, :user_id).each { |pid, uid| map[pid] << uid if uid }
    Collaborator.kept.where(collaboratable_type: "Project", collaboratable_id: project_ids)
      .pluck(:collaboratable_id, :user_id).each { |pid, uid| map[pid] << uid if uid }
    map.transform_values(&:uniq)
  end

  # Approved-ship projects these members draw approved hours from (as journal author or
  # journal collaborator — the only ways public approved seconds are attributed). Bounds the
  # proportional-hours scan to the data feeding these members' totals instead of the whole program.
  def attributable_project_ids(member_ids)
    authored = JournalEntry.kept.joins(:ship)
      .where(ships: { status: Ship.statuses[:approved] }, user_id: member_ids)
      .distinct.pluck(:project_id)
    collab = JournalEntry.kept.joins(:ship)
      .where(ships: { status: Ship.statuses[:approved] })
      .where(id: Collaborator.kept.where(collaboratable_type: "JournalEntry", user_id: member_ids).select(:collaboratable_id))
      .distinct.pluck(:project_id)
    (authored + collab).uniq
  end

  # { ship_id => { user_id => projected_added_seconds } } for ships whose TA has approved.
  # Mirrors batch_user_approved_seconds: the TA-approved pool split by each member's share of
  # the current ship's journal time.
  def projected_increment_by_ship_user
    ta_ships = @ships.select do |s|
      ta = s.time_audit_review
      ta&.approved? && ta.approved_public_seconds.to_i.positive?
    end
    return {} if ta_ships.empty?

    je_rows = JournalEntry.kept.where(ship_id: ta_ships.map(&:id)).pluck(:id, :ship_id)
    return {} if je_rows.empty?

    je_ids = je_rows.map(&:first)
    ship_by_je = je_rows.to_h
    seconds_by_je = JournalEntry.batch_time_logged(je_ids)
    attribution = attribution_sets(je_ids)

    total_by_ship = Hash.new(0)
    user_by_ship = Hash.new { |h, k| h[k] = Hash.new(0) }
    je_ids.each do |je_id|
      sid = ship_by_je[je_id]
      secs = seconds_by_je[je_id].to_i
      total_by_ship[sid] += secs
      attr_set = attribution[je_id]
      next if attr_set.nil? || attr_set.empty?
      share = secs / attr_set.size
      attr_set.each { |uid| user_by_ship[sid][uid] += share }
    end

    ta_ships.each_with_object({}) do |ship, result|
      total = total_by_ship[ship.id].to_i
      next unless total.positive?
      pool = ship.time_audit_review.approved_public_seconds.to_i
      result[ship.id] = user_by_ship[ship.id].transform_values { |us| (pool * us) / total }
    end
  end

  # { je_id => [attributed_user_id, ...] } — author plus kept journal collaborators.
  def attribution_sets(je_ids)
    extras = JournalEntry.batch_attributed_user_ids(je_ids)
    JournalEntry.where(id: je_ids).pluck(:id, :user_id).each_with_object({}) do |(je_id, author_id), h|
      next if author_id.nil?
      h[je_id] = ([ author_id ] | (extras[je_id] || [])).uniq
    end
  end
end
