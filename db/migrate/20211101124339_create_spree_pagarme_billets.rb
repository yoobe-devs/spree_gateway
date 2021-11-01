class CreateSpreePagarmeBillets < ActiveRecord::Migration[6.1]
  def change
    create_table :spree_pagarme_billets do |t|
      t.date :expiration_date
      t.string :billet_url
      t.string :token
      t.references :payment
      
      t.timestamps
    end
  end
end
