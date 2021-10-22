class AddColumnPagarmeIdToSpreeUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :spree_users, :pagarme_id, :string
  end
end
