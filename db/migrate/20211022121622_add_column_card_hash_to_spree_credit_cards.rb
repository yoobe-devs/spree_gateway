class AddColumnCardHashToSpreeCreditCards < ActiveRecord::Migration[6.1]
  def change
    add_column :spree_credit_cards, :card_hash, :string
  end
end
