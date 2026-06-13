# frozen_string_literal: true

# Computes what changed in a project's repo since the last relevant review, for
# surfacing on re-ship review pages. Anchors on the prior review's stored commit
# SHA; falls back to the commit at the prior review's completion time when no SHA
# was stored (older reviews) or the stored SHA was force-pushed out of the repo.
module ReviewRepoDiffService
  CACHE_TTL = 6.hours

  module_function

  # ship: the ship being reviewed. anchor_review: the most recent completed
  # review to diff against (nil for a first review → returns nil).
  # Returns a summary hash or nil when there's nothing to compare.
  def call(ship:, anchor_review:)
    return nil unless anchor_review

    owner, repo = GithubService.parse_repo(ship.project.repo_link)
    return nil unless owner

    head = GithubService.head_commit_sha(owner, repo)
    return nil unless head

    Rails.cache.fetch(cache_key(owner, repo, anchor_review, head), expires_in: CACHE_TTL) do
      compute(owner, repo, anchor_review, head)
    end
  end

  def compute(owner, repo, anchor_review, head)
    basis = "sha"
    base = anchor_review.reviewed_commit_sha.presence
    result = base && GithubService.compare(owner, repo, base, head)

    if result.nil? # no stored SHA, or it was force-pushed away — fall back to the completion date
      basis = "date"
      base = GithubService.commit_sha_at(owner, repo, anchor_review.completed_at)
      result = base && GithubService.compare(owner, repo, base, head)
    end
    return nil unless result

    summarize(result, basis:, base:, head:, anchor_review:)
  end

  def summarize(result, basis:, base:, head:, anchor_review:)
    files = result[:files]
    {
      commits: result[:total_commits],
      added: files.count { |f| f[:status] == "added" },
      modified: files.count { |f| %w[modified changed].include?(f[:status]) },
      removed: files.count { |f| f[:status] == "removed" },
      renamed: files.count { |f| f[:status] == "renamed" },
      files: files,
      basis: basis, # "sha" = exact anchor; "date" = approximated from completion time
      since: anchor_review.completed_at&.iso8601,
      anchor_review_type: anchor_review.class.name.underscore,
      base_sha: base,
      head_sha: head
    }
  end

  # Content-addressed on base anchor + current HEAD so a new push or a moved
  # anchor produces a fresh key — never serves a stale diff.
  def cache_key(owner, repo, anchor_review, head)
    base_part = anchor_review.reviewed_commit_sha.presence || "t#{anchor_review.completed_at&.to_i}"
    "review_repo_diff/v1/#{owner}/#{repo}/#{anchor_review.class.name}/#{anchor_review.id}/#{base_part}/#{head}"
  end
end
