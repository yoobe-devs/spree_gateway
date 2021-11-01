module SpreeGateway
  module PaymentDecorator
    def self.prepended(base)
      base.has_one :pagarme_billet, class_name: '::Spree::PagarmeBillet'
    end

    def handle_response(response, success_state, failure_state)
      record_response(response)
      
      if response.success?
        unless response.authorization.nil?
          self.response_code = response.authorization
          self.avs_response = response.avs_result["code"]

          if response.cvv_result
            self.cvv_response_code = response.cvv_result["code"]
            self.cvv_response_message = response.cvv_result["message"]
          end
        end
        send("#{success_state}!")
      elsif (payment_method.type == "Spree::Gateway::PagarmeBoleto") && (response.params["status"] == "waiting_payment")
        pagarme_billet.update({
                                billet_url: response.params["boleto_url"],
                                expiration_date: response.params["boleto_expiration_date"],
                                billet_code: response.params["boleto_barcode"],
                              })
        pend
        pending?
      else
        send(failure_state)
        gateway_error(response)
      end
    end

    def handle_payment_preconditions
      raise ArgumentError, "handle_payment_preconditions must be called with a block" unless block_given?

      if payment_method&.source_required?
        if source
          unless processing?
            if payment_method.supports?(source) || token_based?
              yield
            else
              invalidate!
              raise Core::GatewayError, Spree.t(:payment_method_not_supported)
            end
          end
        else
          raise Core::GatewayError, Spree.t(:payment_processing_failed)
        end
      elsif payment_method.type == "Spree::Gateway::PagarmeBoleto"
        yield
      end
    end

    def verify!(**options)
      process_verification(options)
    end

    private

    def process_verification(**options)
      protect_from_connection_error do
        response = payment_method.verify(source, options)

        record_response(response)

        if response.success?
          unless response.authorization.nil?
            self.response_code = response.authorization

            source.update(status: response.params['status'])
          end
        else
          gateway_error(response)
        end
      end
    end
  end
end

::Spree::Payment.prepend(::SpreeGateway::PaymentDecorator)
