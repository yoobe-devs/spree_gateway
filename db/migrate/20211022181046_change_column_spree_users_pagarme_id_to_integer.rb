class ChangeColumnSpreeUsersPagarmeIdToInteger < ActiveRecord::Migration[6.1]
  def change
    change_column :spree_users, :pagarme_id, :integer, using: 'pagarme_id::integer'
  end
end
