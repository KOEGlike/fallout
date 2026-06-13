class AddRepoDiffToReviews < ActiveRecord::Migration[8.1]
  def change
    # Cached "changes since last review" summary, computed once on review creation (like repo_tree).
    add_column :requirements_check_reviews, :repo_diff, :jsonb
    add_column :design_reviews, :repo_diff, :jsonb
    add_column :build_reviews, :repo_diff, :jsonb
  end
end
