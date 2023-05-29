module Spree
  class Gateway::Pagarme < Gateway
    preference :api_key, :string
    preference :secret_key, :string
    preference :crypto_key, :string

    def method_type
      "pagarme"
    end

    def provider_class
      ActiveMerchant::Billing::PagarmeGateway
    end

    def payment_profiles_supported?
      true
    end

    def purchase(money, creditcard, gateway_options)
      provider.purchase(money, creditcard, gateway_options)
    end

    def authorize(money, creditcard, gateway_options)
      provider.authorize(money, creditcard, gateway_options)
    end

    def capture(money, response_code, gateway_options)
      provider.capture(money, response_code, gateway_options)
    end

    def credit(money, creditcard, response_code, gateway_options)
      provider.refund(money, response_code, {})
    end

    def void(response_code, creditcard, gateway_options)
      provider.void(response_code, {})
    end

    def cancel(response_code)
      provider.void(response_code, {})
    end

    def create_profile(payment)
      return unless payment.source.gateway_customer_profile_id.nil?
      user = payment.order.user

      if user.pagarme_id.blank?
        create_customer(payment)
      else
        payment.source.update!({
          gateway_customer_profile_id: user.pagarme_id,
        })
      end
      add_card(payment) if payment.source.gateway_payment_profile_id.blank?
    end

    private

    def create_customer(payment)
      user = payment.order.user
      response = provider.customer(customer_params(payment))
      if response.success?
        id = response.try(:params).try(:fetch, "id")
        payment.source.update!({ gateway_customer_profile_id: id})
        user.update!({pagarme_id: id})
      else
        payment.send(:gateway_error, response.message)
      end
    end

    def add_card(payment)
      user = payment.order.user
      cc = payment.source

      creditcard = user.credit_cards
                       .where(card_hash: credit_card_hash(cc))
                       .where.not(id: cc.id)
                       .first

      if creditcard.blank?
        response = provider.credit_card(user.pagarme_id, cc)

        if response.success?
          payment.source.update!({
            cc_type: response.params["brand"],
            gateway_payment_profile_id: response.params["id"],
            card_hash: credit_card_hash(cc),
          })
        else
          payment.send(:gateway_error, response.message)
        end
      else
        payment.source.update!({
          cc_type: creditcard.cc_type,
          gateway_payment_profile_id: creditcard.gateway_payment_profile_id,
          card_hash: creditcard.card_hash,
        })
      end
    end

    # Generate a uniq hash to identify already use credit cards
    def credit_card_hash(cc)
      Digest::SHA1.hexdigest "#{cc.name}|#{cc.number}|#{cc.month}|#{cc.year}|#{cc.user_id}|#{cc.payment_method_id}"
    end

    def purchase_params(payment)
      metadata = {
        email: payment.order.email,
        order_id: payment.order.id,
        ip: payment.order.last_ip_address,
        customer: payment.order.billing_address.full_name,
      }.merge! address_for(payment)
    end

    def purchase_metadata(payment)
      metadata = {
        email: payment.order.email,
        order_id: payment.order.id,
        ip: payment.order.last_ip_address,
        customer: payment.order.billing_address.full_name,
      }
    end

    def customer_params(payment)
      user = payment.order.user
      normalized_document = user.document_value.gsub(/[^0-9]/, "")
      document_type = normalized_document&.size == 11 ? "cpf" : "cnpj"

      options = {
        external_id: user.id.to_s,
        name: user.full_name,
        email: payment.order.email,
        documents: [{
          type: document_type,
          number: normalized_document,
        }],
        phone_numbers: [],
        type: "individual",
        country: "br",
      }

      options[:phone_numbers] << format_phone_number(user.phone) unless user.phone.blank?

      options
    end

    def format_phone_number(number)
      number.gsub! /\D/, ""
      number.size > 11 ? "+#{number}": "+55#{number}"
    end

    # In this gateway, what we call 'secret_key' is the 'login'
    def options
      super.merge(
        login: preferred_secret_key,
        application: app_info,
      )
    end

    def options_for_purchase_or_auth(money, creditcard, gateway_options)
      options = {}
      options[:description] = "Spree Order ID: #{gateway_options[:order_id]}"
      options[:currency] = gateway_options[:currency]
      options[:application] = app_info

      if customer = creditcard.gateway_customer_profile_id
        options[:customer] = customer
      end
      if token_or_card_id = creditcard.gateway_payment_profile_id
        # The Stripe ActiveMerchant gateway supports passing the token directly as the creditcard parameter
        # The Stripe ActiveMerchant gateway supports passing the customer_id and credit_card id
        # https://github.com/Shopify/active_merchant/issues/770
        creditcard = token_or_card_id
      end
      return money, creditcard, options
    end

    def update_source!(source)
      # source.cc_type = CARD_TYPE_MAPPING[source.cc_type] if CARD_TYPE_MAPPING.include?(source.cc_type
      source
    end

    def app_info
      name_with_version = "SpreeGateway/#{SpreeGateway.version}"
      url = "https://spreecommerce.org"
      "#{name_with_version} #{url}"
    end
  end
end
