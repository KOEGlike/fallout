class RenameApprovedSecondsToApprovedPublicSeconds < ActiveRecord::Migration[8.1]
  def change
    rename_column :ships, :approved_seconds, :approved_public_seconds
    rename_column :time_audit_reviews, :approved_seconds, :approved_public_seconds
  end
end
