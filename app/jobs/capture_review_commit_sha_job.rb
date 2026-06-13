# frozen_string_literal: true

# Records the repo's current HEAD commit SHA when a code review (RC/DR/BR) is
# finalized — this becomes the anchor for the next ship's "changes since last
# review" diff. Enqueued from Reviewable on terminal transitions.
class CaptureReviewCommitShaJob < ApplicationJob
  queue_as :background

  def perform(review_type, review_id)
    return unless Reviewable::REVIEW_MODELS.include?(review_type) # guard constantize against arbitrary input

    review = review_type.constantize.find_by(id: review_id)
    return unless review.respond_to?(:reviewed_commit_sha)
    return if review.reviewed_commit_sha.present? # already captured — don't re-hit the API

    owner, repo = GithubService.parse_repo(review.ship.project.repo_link)
    return unless owner

    sha = GithubService.head_commit_sha(owner, repo)
    review.update_columns(reviewed_commit_sha: sha) if sha # Don't clobber with nil on API failure
  end
end
