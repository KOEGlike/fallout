# Bulk equivalents of User#total_time_logged_seconds and the admin "build_approved" total,
# computed for every user at once in a handful of queries instead of ~12 per user. Results are
# byte-identical to Project.batch_user_logged_seconds / batch_user_internal_approved_seconds
# summed per user — the same per-journal and per-project integer-division shares, just pivoted
# to aggregate by user. Used by the admin hours-stats dashboard so it can compute live (hours
# must stay current) without timing the request out.
class HoursStatsCalculator
  # { user_id => logged_seconds } across all users.
  def self.logged_seconds_by_user
    new.logged_seconds_by_user
  end

  # { user_id => internal-approved_seconds } across all users.
  def self.internal_approved_seconds_by_user
    new.internal_approved_seconds_by_user
  end

  def logged_seconds_by_user
    result = Hash.new(0)
    add_journal_shares(result, journal_attribution)
    add_manual_shares(result)
    result
  end

  def internal_approved_seconds_by_user
    internal_by_project = Ship.where(status: :approved)
      .joins(:project)
      .left_joins(:design_review, :build_review)
      .where(projects: { discarded_at: nil })
      .group("projects.id")
      .sum(Arel.sql("COALESCE(ships.approved_public_seconds, 0) + COALESCE(design_reviews.hours_adjustment, 0) + COALESCE(build_reviews.hours_adjustment, 0)"))
    return {} if internal_by_project.empty?

    candidate_ids = internal_by_project.keys

    # Journal entries claimed by approved ships on the candidate projects — the approved-cycle
    # denominator/numerator, matching batch_approved_cycle_attribution.
    approved_je = JournalEntry.kept
      .joins(:ship)
      .where(project_id: candidate_ids, ships: { status: Ship.statuses[:approved] })
      .pluck(:id, :project_id)
    return {} if approved_je.empty?

    je_ids = approved_je.map(&:first)
    project_by_je = approved_je.to_h
    seconds_by_je = JournalEntry.batch_time_logged(je_ids)

    total_by_project = Hash.new(0)         # { project_id => total approved-cycle seconds }
    user_by_project = Hash.new { |h, k| h[k] = Hash.new(0) } # { project_id => { user_id => seconds } }

    attribution = journal_attribution(je_ids)
    je_ids.each do |je_id|
      pid = project_by_je[je_id]
      secs = seconds_by_je[je_id].to_i
      total_by_project[pid] += secs
      attr_set = attribution[je_id]
      next if attr_set.nil? || attr_set.empty?
      share = secs / attr_set.size
      attr_set.each { |uid| user_by_project[pid][uid] += share }
    end

    result = Hash.new(0)
    candidate_ids.each do |pid|
      total = total_by_project[pid].to_i
      next unless total.positive?
      internal = internal_by_project[pid].to_i
      user_by_project[pid].each do |uid, user_share|
        result[uid] += (internal * user_share) / total
      end
    end
    result
  end

  private

  # { je_id => [attributed_user_id, ...] } — the journal's author plus its kept, non-discarded
  # collaborators, exactly the attribution set used by JournalEntry.batch_user_attributed_seconds.
  def journal_attribution(je_ids = nil)
    authors = if je_ids
      JournalEntry.where(id: je_ids).pluck(:id, :user_id)
    else
      JournalEntry.kept.pluck(:id, :user_id)
    end
    extras = JournalEntry.batch_attributed_user_ids(authors.map(&:first))

    authors.each_with_object({}) do |(je_id, author_id), h|
      next if author_id.nil?
      h[je_id] = ([ author_id ] | (extras[je_id] || [])).uniq
    end
  end

  # Adds each user's per-journal share of recording seconds (journal_seconds / attribution_size).
  def add_journal_shares(result, attribution)
    seconds_by_je = JournalEntry.batch_time_logged(attribution.keys)
    attribution.each do |je_id, attr_set|
      next if attr_set.empty?
      share = seconds_by_je[je_id].to_i / attr_set.size
      attr_set.each { |uid| result[uid] += share }
    end
  end

  # Adds each member's per-member share of project manual_seconds (manual / member_count),
  # mirroring batch_user_logged_seconds: denominator counts verified, kept members; recipients
  # are the owner and kept collaborators. Discarded projects only attribute manual to members
  # who have journal involvement there (matching projects_attributable_to_self_ids).
  def add_manual_shares(result)
    projects = Project.where("manual_seconds > 0").pluck(:id, :user_id, :manual_seconds, :discarded_at)
    return if projects.empty?

    project_ids = projects.map(&:first)
    member_counts = Project.batch_member_counts(project_ids)
    collabs_by_project = Collaborator.kept
      .where(collaboratable_type: "Project", collaboratable_id: project_ids)
      .pluck(:collaboratable_id, :user_id)
      .group_by(&:first)
      .transform_values { |pairs| pairs.map(&:last) }

    # Users with journal involvement per project (author or journal collaborator) — used to gate
    # manual attribution on discarded projects, where membership alone isn't in the attributable set.
    journal_users_by_project = journal_users_by_project(project_ids)

    projects.each do |pid, owner_id, manual_seconds, discarded_at|
      mc = member_counts[pid].to_i
      next unless mc.positive?
      share = manual_seconds.to_i / mc

      members = ([ owner_id ] + (collabs_by_project[pid] || [])).uniq
      members.each do |uid|
        next if discarded_at && !journal_users_by_project[pid]&.include?(uid)
        result[uid] += share
      end
    end
  end

  # { project_id => Set(user_ids) } for users who authored or are journal-collaborators on a kept
  # journal entry of the project — the journal-attributable members for discarded-project manual.
  def journal_users_by_project(project_ids)
    map = Hash.new { |h, k| h[k] = Set.new }
    JournalEntry.kept.where(project_id: project_ids).pluck(:id, :project_id, :user_id).each do |_je_id, pid, author_id|
      map[pid] << author_id if author_id
    end
    je_rows = JournalEntry.kept.where(project_id: project_ids).pluck(:id, :project_id)
    extras = JournalEntry.batch_attributed_user_ids(je_rows.map(&:first))
    project_by_je = je_rows.to_h
    extras.each do |je_id, user_ids|
      pid = project_by_je[je_id]
      user_ids.each { |uid| map[pid] << uid }
    end
    map
  end
end
