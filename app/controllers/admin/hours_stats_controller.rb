class Admin::HoursStatsController < Admin::ApplicationController
  before_action :require_admin! # admin only

  MODES = %w[logged build_approved].freeze

  def index
    skip_policy_scope
    mode = MODES.include?(params[:mode]) ? params[:mode] : "logged"

    render inertia: "admin/hours_stats/index", props: {
      buckets: compute_buckets(mode).map { |range, users| { range: range, users: users } },
      computed_at: Time.current.iso8601,
      mode: mode
    }
  end

  def refresh
    skip_authorization
    # Stats are computed live on every load, so a refresh is just a reload.
    redirect_to admin_hours_stats_path(mode: params[:mode])
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

  # Computed live in a handful of bulk queries (see HoursStatsCalculator) so the dashboard
  # always reflects current hours — the previous per-user loop ran ~12 queries per user and
  # timed out the request on a cold 24h cache / refresh.
  def compute_buckets(mode)
    users = User.kept.verified.to_a
    return BUCKETS.transform_values { [] } if users.empty?

    user_seconds = if mode == "build_approved"
      HoursStatsCalculator.internal_approved_seconds_by_user
    else
      HoursStatsCalculator.logged_seconds_by_user
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
