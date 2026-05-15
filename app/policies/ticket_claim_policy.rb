# frozen_string_literal: true

class TicketClaimPolicy < ApplicationPolicy
  def new?
    create?
  end

  def create?
    # Only non-trial, authenticated users with >= 60 approved hours can claim
    !user.trial? && approved_hours >= 60
  end

  private

  def approved_hours
    (user.approved_time_logged_seconds / 3600.0).round(1)
  end
end
