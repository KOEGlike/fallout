class Dev::RepoDiffPreviewController < ApplicationController
  allow_unauthenticated_access only: :show # Dev-only static UI sandbox, no data access
  # No model to authorize — static mock page (no index action, so blanket skip)
  skip_after_action :verify_authorized
  skip_after_action :verify_policy_scoped

  def show
    render inertia: "dev/RepoDiffPreview"
  end
end
