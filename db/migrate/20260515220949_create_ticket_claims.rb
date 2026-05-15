class CreateTicketClaims < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_claims do |t|
      t.references :user, null: false, foreign_key: true
      t.string :state, null: false, default: "pending"

      t.timestamps
    end

    # Enforce one claim per user at the DB level — index already created by t.references above
    remove_index :ticket_claims, :user_id
    add_index :ticket_claims, :user_id, unique: true
  end
end
