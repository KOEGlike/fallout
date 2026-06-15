class Admin::KoiTransactionsController < Admin::ApplicationController
  before_action :require_admin! # Only admins can adjust koi/gold balances

  def index
    # policy_scope runs on the critical path so verify_policy_scoped passes on the initial
    # (deferred) render; it's lazy, so no query fires until the deferred loader enumerates it.
    scope = policy_scope(transaction_model)

    render inertia: "admin/koi_transactions/index", props: {
      user_id_filter: params[:user_id].to_s,
      currency: current_currency,
      **deferred_index_props(scope)
    }
  end

  def new
    model = transaction_model
    @transaction = model.new
    @transaction.user_id = params[:user_id] if params[:user_id].present?
    authorize @transaction

    render inertia: "admin/koi_transactions/new", props: {
      prefill_user_id: params[:user_id].to_s,
      currency: current_currency
    }
  end

  def create
    model = transaction_model
    @transaction = model.new(transaction_params)
    @transaction.actor = current_user
    @transaction.reason = "admin_adjustment"
    authorize @transaction

    if @transaction.save
      redirect_to admin_koi_transactions_path(user_id: @transaction.user_id, currency: current_currency),
        notice: "#{current_currency.capitalize} adjustment saved."
    else
      redirect_back fallback_location: new_admin_koi_transaction_path(currency: current_currency),
        inertia: { errors: @transaction.errors.messages }
    end
  end

  private

  # Memoized loader shared by the deferred index props so the heavy query runs once per
  # deferred request even though transactions/pagy are separate Inertia props.
  def deferred_index_props(scope)
    memo = nil
    load = lambda do
      memo ||= begin
        base_scope = scope.includes(:user, :actor)
        base_scope = base_scope.where(user_id: params[:user_id]) if params[:user_id].present?
        @pagy, @transactions = pagy(base_scope.order(created_at: :desc))
        { transactions: @transactions.map { |t| serialize_transaction(t) }, pagy: pagy_props(@pagy) }
      end
    end
    {
      transactions: InertiaRails.defer(group: "index") { load.call[:transactions] },
      pagy: InertiaRails.defer(group: "index") { load.call[:pagy] }
    }
  end

  def current_currency
    params[:currency] == "gold" ? "gold" : "koi"
  end

  def transaction_model
    current_currency == "gold" ? GoldTransaction : KoiTransaction
  end

  def transaction_params
    if current_currency == "gold"
      params.expect(gold_transaction: [ :user_id, :amount, :description ])
    else
      params.expect(koi_transaction: [ :user_id, :amount, :description ])
    end
  end

  def serialize_transaction(txn)
    {
      id: txn.id,
      user: { id: txn.user.id, display_name: txn.user.display_name },
      actor: txn.actor ? { id: txn.actor.id, display_name: txn.actor.display_name } : nil,
      amount: txn.amount,
      reason: txn.reason,
      description: txn.description,
      created_at: txn.created_at.strftime("%b %d, %Y %H:%M")
    }
  end
end
