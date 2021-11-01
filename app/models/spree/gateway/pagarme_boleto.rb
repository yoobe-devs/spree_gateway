module Spree
  class Gateway::PagarmeBoleto < Gateway::Pagarme

    def source_required?
      false
    end
  end
end
