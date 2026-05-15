# == Schema Information
#
# Table name: ticket_claims
#
#  id         :bigint           not null, primary key
#  state      :string           default("pending"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_ticket_claims_on_user_id  (user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class TicketClaim < ApplicationRecord
  STATES = %w[pending approved rejected].freeze

  belongs_to :user

  enum :state, { pending: "pending", approved: "approved", rejected: "rejected" }, validate: true

  validates :state, inclusion: { in: STATES }
  validates :user_id, uniqueness: true # One claim per user enforced at both DB and model level
end
