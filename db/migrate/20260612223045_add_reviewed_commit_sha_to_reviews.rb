class AddReviewedCommitShaToReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :requirements_check_reviews, :reviewed_commit_sha, :string
    add_column :design_reviews, :reviewed_commit_sha, :string
    add_column :build_reviews, :reviewed_commit_sha, :string
  end
end
