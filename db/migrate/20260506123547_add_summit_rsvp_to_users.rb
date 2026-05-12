class AddSummitRsvpToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :summit_rsvp, :string
  end
end
