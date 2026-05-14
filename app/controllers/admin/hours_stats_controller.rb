class Admin::HoursStatsController < Admin::ApplicationController
  before_action :require_admin! # admin only

  CACHE_KEY = "admin/hours_stats/%s"
  CACHE_TTL = 24.hours
  MODES = %w[logged build_approved].freeze

  def index
    skip_policy_scope
    mode = MODES.include?(params[:mode]) ? params[:mode] : "logged"

    data = Rails.cache.fetch(format(CACHE_KEY, mode), expires_in: CACHE_TTL) do
      { buckets: compute_stats(mode), cached_at: Time.current.iso8601 }
    end

    render inertia: "admin/hours_stats/index", props: {
      buckets: data[:buckets].map { |range, users| { range: range, users: users } },
      cached_at: data[:cached_at],
      mode: mode
    }
  end

  def refresh
    skip_authorization
    MODES.each { |m| Rails.cache.delete(format(CACHE_KEY, m)) }
    redirect_to admin_hours_stats_path, notice: "Stats refreshed."
  end

  private

  BUCKETS = { "1-10h" => [], "11-20h" => [], "21-30h" => [], "31-40h" => [], "41-50h" => [], "51-60h" => [], "60+" => [] }.freeze

  def bucket_for(hours)
    case hours
    when 1...11 then "1-10h"
    when 11...21 then "11-20h"
    when 21...31 then "21-30h"
    when 31...41 then "31-40h"
    when 41...51 then "41-50h"
    when 51...61 then "51-60h"
    else "60+"
    end
  end

  def compute_stats(mode)
    users = User.kept.verified.to_a
    return BUCKETS.transform_values { [] } if users.empty?

    # Per-user attribution drives both modes — each user's value is computed via the
    # canonical journal-attribution helpers, so admin buckets agree with the profile
    # totals / shop 60h bar / path 60h dialog gate. Iterates users in Ruby because the
    # cache TTL is 24h; if this turns slow at scale, hoist into a single SQL aggregation.
    user_seconds = users.to_h do |u|
      ids = u.projects_attributable_to_self_ids
      seconds = if mode == "build_approved"
        Project.batch_user_internal_approved_seconds(ids, u).values.sum
      else
        Project.batch_user_logged_seconds(ids, u).values.sum
      end
      [ u.id, seconds ]
    end

    build_user_buckets(user_seconds, users)
  end

  def build_user_buckets(user_seconds, users)
    buckets = BUCKETS.transform_values { [] }
    users.each do |u|
      seconds = user_seconds[u.id].to_i
      next if seconds < 3600
      h = seconds / 3600.0
      buckets[bucket_for(h)] << { email: u.email, slack_id: u.slack_id, hours: h.round(2) }
    end
    buckets.transform_values { |entries| entries.sort_by { |e| -e[:hours] } }
  end
end
