module Spree
  class PagarmeBillet < ApplicationRecord
    belongs_to :payment, class_name: 'Spree::Payment'
  end
end