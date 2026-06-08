class CreateReviewerSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :reviewer_settings do |t|
      t.decimal :ta_hours_per_review_equivalent

      t.timestamps
    end
  end
end
