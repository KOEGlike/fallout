# frozen_string_literal: true

# Computes and caches the "changes since last review" summary on a review's
# repo_diff column. Enqueued on review creation (RC/DR/BR), mirroring
# FetchRepoTreeJob — the result is a near-submission snapshot, not live.
class ComputeReviewRepoDiffJob < ApplicationJob
  queue_as :background

  def perform(review_type, review_id)
    return unless Reviewable::REVIEW_MODELS.include?(review_type) # guard constantize against arbitrary input

    review = review_type.constantize.find_by(id: review_id)
    return unless review.respond_to?(:repo_diff) # TA has no such column

    diff = ReviewRepoDiffService.for_review(review)
    review.update_columns(repo_diff: diff) if diff # Leave column nil (card hidden) when there's nothing to compare
  end
end
