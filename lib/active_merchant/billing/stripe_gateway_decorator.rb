module ActiveMerchant
  module Billing
    module StripeGatewayDecorator

      def create_post_for_auth_or_purchase(money, payment, options)
        post = {}

        if payment.is_a?(StripePaymentToken)
          add_payment_token(post, payment, options)
        else
          add_creditcard(post, payment, options)
        end

        add_charge_details(post, money, payment, options)
        post
      end


      def verify(source, **options)
        customer = source.gateway_customer_profile_id
        bank_account_token = source.gateway_payment_profile_id

        commit(:post, "customers/#{CGI.escape(customer)}/sources/#{bank_account_token}/verify", amounts: options[:amounts])
      end

      def retrieve(source, **options)
        customer = source.gateway_customer_profile_id
        bank_account_token = source.gateway_payment_profile_id
        commit(:get, "customers/#{CGI.escape(customer)}/bank_accounts/#{bank_account_token}")
      end

      private

      def headers(options = {})
        headers = super
        headers['User-Agent'] = headers['X-Stripe-Client-User-Agent']
        headers
      end

      def add_customer_data(post, options)
        super
        post[:payment_user_agent] = "SpreeGateway/#{SpreeGateway.version}"
      end
    end
  end
end

ActiveMerchant::Billing::StripeGateway.prepend(ActiveMerchant::Billing::StripeGatewayDecorator)
