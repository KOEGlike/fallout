class ProjectGrantOrderPolicy < ApplicationPolicy
  # User-facing actions: any full-account user can request a grant for themselves.
  def index? = full_user?
  def new? = full_user?
  def create? = full_user? && record.user_id == user&.id

  # Admins (without hcb) are view-only for every money-adjacent surface: they can
  # browse orders + settings + warnings but cannot change state, reconcile, fulfill,
  # refund, or edit settings. The `hcb` role is required for every write.
  def show? = admin?
  def update? = hcb?
  def fulfill? = hcb?
  def batch_fulfill? = hcb?
  def reconcile_pending_topup? = hcb?
  def mark_topup_completed? = hcb?
  def refund? = hcb?

  class Scope < ApplicationPolicy::Scope
    # Admins see everything; full users see only their own. Others get nothing.
    def resolve
      return scope.all if user&.admin?
      return scope.none unless user.present? && !user.trial?

      scope.where(user_id: user.id)
    end
  end

  private

  def full_user?
    user.present? && !user.trial?
  end

  def hcb?
    user&.hcb?
  end
end
