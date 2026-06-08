# frozen_string_literal: true

class AddFrozenGoldAmountToProjectGrantOrders < ActiveRecord::Migration[8.1]
  def change
    # Grants deplete koi first, then gold. frozen_koi_amount holds the koi portion,
    # frozen_gold_amount the remainder. Existing orders were paid entirely in koi.
    add_column :project_grant_orders, :frozen_gold_amount, :integer, null: false, default: 0
  end
end
