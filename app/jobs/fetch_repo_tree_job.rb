# frozen_string_literal: true

class FetchRepoTreeJob < ApplicationJob
  queue_as :background

  def perform(review_id)
    review = RequirementsCheckReview.find_by(id: review_id)
    return unless review # Review may have been deleted between enqueue and execution

    owner, repo = GithubService.parse_repo(review.ship.project.repo_link)
    return unless owner

    tree = GithubService.repo_tree(owner, repo)
    review.update_columns(repo_tree: tree) if tree # Don't overwrite existing data with nil on API failure
  end
end
