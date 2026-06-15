class Admin::ShopOrdersController < Admin::ApplicationController
  before_action :require_admin! # Only admins manage orders, not reviewers

  def index
    # policy_scope runs on the critical path so verify_policy_scoped passes on the initial
    # (deferred) render; it's lazy, so no query fires until the deferred loader enumerates it.
    scope = policy_scope(ShopOrder)
    render inertia: "admin/shop_orders/index", props: {
      state_filter: params[:state].to_s,
      **deferred_index_props(scope)
    }
  end

  def show
    @order = ShopOrder.find(params[:id])
    authorize @order

    render inertia: "admin/shop_orders/show", props: {
      order: serialize_order_detail(@order)
    }
  end

  def update
    @order = ShopOrder.find(params[:id])
    authorize @order

    was_rejected = @order.rejected?
    if @order.update(order_params)
      revoke_streak_freeze(@order, was_rejected)
      redirect_to admin_shop_order_path(@order), notice: "Order updated."
    else
      redirect_back fallback_location: admin_shop_order_path(@order),
        inertia: { errors: @order.errors.messages }
    end
  end

  private

  # Memoized loader shared by the deferred index props so the heavy query runs once per
  # deferred request even though orders/pagy are separate Inertia props.
  def deferred_index_props(scope)
    memo = nil
    load = lambda do
      memo ||= begin
        base_scope = scope.includes(:user, :shop_item)
        base_scope = base_scope.where(state: params[:state]) if params[:state].present?
        @pagy, @orders = pagy(base_scope.order(created_at: :desc))
        { orders: @orders.map { |o| serialize_order_row(o) }, pagy: pagy_props(@pagy) }
      end
    end
    {
      orders: InertiaRails.defer(group: "index") { load.call[:orders] },
      pagy: InertiaRails.defer(group: "index") { load.call[:pagy] }
    }
  end

  def revoke_streak_freeze(order, was_rejected_before)
    # If a streak freeze order is newly rejected, decrement the user's streak freezes to match the refund
    return if was_rejected_before
    return unless order.rejected? && order.shop_item.grants_streak_freeze?

    User.where(id: order.user_id).where("streak_freezes >= ?", order.quantity)
        .update_all([ "streak_freezes = streak_freezes - ?", order.quantity ])
  end

  def order_params
    params.expect(shop_order: [ :state, :admin_note ])
  end

  def serialize_order_row(order)
    {
      id: order.id,
      user: { id: order.user.id, display_name: order.user.display_name, email: order.user.email },
      shop_item: { id: order.shop_item.id, name: order.shop_item.name },
      frozen_price: order.frozen_price,
      quantity: order.quantity,
      total_cost: order.frozen_price * order.quantity,
      state: order.state,
      created_at: order.created_at.strftime("%b %d, %Y %H:%M")
    }
  end

  def serialize_order_detail(order)
    serialize_order_row(order).merge(
      address: order.address,
      phone: order.phone,
      admin_note: order.admin_note,
      user_koi_balance: order.user.koi
    )
  end
end
