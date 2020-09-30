module ActiveMerchant
  module Billing
    module PagarmeGatewayDecorator
      def self.prepended(base)
        base.supported_cardtypes += %i[american_express aura diners_club discover elo hipercard jcb master visa]

        # TODO: poder mudar para ambiente de teste
        # base.live_url = 'https://api.pagar.me/1/'
      end

      def purchase(money, payment_method, gateway_options = {})
        std = ""
        self.wiredump_device = std
        order_id, payment_id = gateway_options[:order_id].split("-")
        order = ::Spree::Order.find_by(number: order_id)
        payment = order.payments.find_by(number: payment_id)

        post = { customer: { id: payment_method.gateway_customer_profile_id } }
        add_amount(post, money)
        add_payment_method(post, payment_method)
        add_metadata(post, gateway_options)
        address_for(post, :billing, order.bill_address)
        shipment_deatils_for(post, order)
        items_for(post, order)

        post[:metadata][:order_id] = order_id
        post[:metadata][:payment_id] = payment_id
        post[:metadata][:ip] = post[:metadata][:ip] || order.last_ip_address

        resp = commit(:post, "transactions", post)
        puts std
        resp
      end

      def authorize(money, payment_method, gateway_options = {})
        order_id, payment_id = gateway_options[:order_id].split("-")
        order = ::Spree::Order.find_by(number: order_id)
        payment = order.payments.find_by(number: payment_id)

        post = { customer: { id: payment_method.gateway_customer_profile_id } }
        add_amount(post, money)
        add_payment_method(post, payment_method)
        add_metadata(post, gateway_options)
        address_for(post, :billing, order.bill_address)
        shipment_deatils_for(post, order)
        items_for(post, order)

        post[:metadata][:order_id] = order_id
        post[:metadata][:payment_id] = payment_id
        post[:metadata][:ip] = post[:metadata][:ip] || order.last_ip_address

        post[:capture] = false

        commit(:post, "transactions", post)
      end

      # Create or Update pagarme customer from Pagarme API
      # @see https://docs.pagar.me/reference#criando-um-cliente
      # @example
      #   params = {
      #     external_id: "#123456789",
      #     name: "João das Neves",
      #     type: "individual", # Options: individual or corporation
      #     country: "br",
      #     email: "joaoneves@norte.com",
      #     documents: [
      #       {
      #         type: "cpf",
      #         number: "11111111111"
      #       }
      #     ],
      #     phone_numbers: [
      #       "+5511999999999",
      #       "+5511888888888"
      #     ],
      #     birthday: "1985-01-01"
      #   }
      #
      # @param [Hash] params Rest api pattern
      def customer(params)
        params = default_customer.merge(params.deep_symbolize_keys)
        resp = commit(:post, "customers", params)
        return resp if resp.success?

        unless resp.params["id"].blank?
          update_params = params.deep_dup.extract!(:name, :email)
          return commit(:put, "customers/#{resp.params["id"]}", update_params)
        end

        resp
      end

      # Create or Retrieve pagarme customer from Pagarme API
      # @see https://docs.pagar.me/reference#criando-um-cliente
      # @example
      #   params = {
      #     "card_expiration_date": "1122",
      #     "card_number": "4018720572598048",
      #     "card_cvv": "123",
      #     "card_holder_name": "Aardvark Silva"
      #   }
      #
      # @param [Hash] params Rest api pattern
      def credit_card(customer_id, source)
        options = { customer_id: customer_id }
        add_credit_card(options, source)

        commit(:post, "cards", options)
      end

      # def verify(source, **options)
      #   customer = source.gateway_customer_profile_id # From Spree: table:spree_credit_cards
      #   bank_account_token = source.gateway_payment_profile_id # From Spree: table:spree_credit_cards

      #   commit(:post, "customers/#{CGI.escape(customer)}/sources/#{bank_account_token}/verify", amounts: options[:amounts])
      # end

      # def retrieve(source, **options)
      #   customer = source.gateway_customer_profile_id
      #   bank_account_token = source.gateway_payment_profile_id
      #   commit(:get, "customers/#{CGI.escape(customer)}/bank_accounts/#{bank_account_token}")
      # end

      private

      def items_for(post, order)
        post[:items] = order.line_items.to_a.map do |line|
          {
            id: line.sku,
            title: line.name,
            unit_price: Money.new(line.price).cents,
            quantity: line.quantity,
            tangible: true,
          }
        end
      end

      def shipment_deatils_for(post, order)
        address_for(post, :shipping, order.ship_address)
        if order.ship_address
          post[:shipping][:fee] = Money.new(order.shipment_total).cents
        end
      end

      def address_for(post, base, address)
        return if address.nil?
        post[base] = {}
        post[base][:name] = address.full_name
        post[base][:address] = {
          street: address.address1,
          street_number: address.address2,
          city: address.city,
          zipcode: address.zipcode,
        }
        if country = address.country
          post[base][:address].merge!(country: country.iso.downcase)
        end
        if state = address.state
          post[base][:address].merge!(state: state.name)
        end
      end

      def headers(options = {})
        {
          "User-Agent" => "Pagar.me/1 ActiveMerchant/#{ActiveMerchant::VERSION}",
          'Content-Type': "application/json",
          'X-PagarMe-Version': "2019-09-01",
        }
      end

      def post_data(params)
        params.merge(api_key: @api_key).to_json
      end

      def success_from(response)
        success_purchase = response.key?("status") && response["status"] == "paid"
        success_authorize = response.key?("status") && response["status"] == "authorized"
        success_refund = response.key?("status") && response["status"] == "refunded"
        from_object = response.key?("object") && %w[card customer].include?(response["object"])

        success_purchase || success_authorize || success_refund || from_object
      end

      def add_credit_card(post, credit_card)
        if credit_card.is_a? String
          post[:card_id] = credit_card
        elsif credit_card.respond_to?(:gateway_payment_profile_id) && !credit_card.gateway_payment_profile_id.blank?
          post[:card_id] = credit_card.gateway_payment_profile_id
        else
          post[:card_number] = credit_card.number
          post[:card_holder_name] = credit_card.name
          post[:card_expiration_date] = "#{credit_card.month}#{credit_card.year}".rjust(4, "0")
          post[:card_cvv] = credit_card.verification_value
        end
      end

      def scrub(transcript)
        transcript.
          gsub(%r((Authorization: Basic )\w+), '\1[FILTERED]').
          gsub(%r(("card_number":\s*)"[^"+]"), '\1"[FILTERED]"').
          gsub(%r(("card_cvv":\s*)"[^"+]"), '\1"[FILTERED]"').
          gsub(%r(("api_key":\s*)"[^"+]"), '\1"[FILTERED]"')
      end

      def default_customer
        {
          type: "individual",
          country: "br",
          phone_numbers: [],
          documents: [],
        }
      end

      # def headers(options = {})
      #   headers = super
      #   headers["User-Agent"] = headers["X-Stripe-Client-User-Agent"]
      #   headers
      # end

      # def add_customer_data(post, options)
      #   super
      #   post[:payment_user_agent] = "SpreeGateway/#{SpreeGateway.version}"
      # end
    end
  end
end

if ActiveMerchant::Billing::PagarmeGateway.included_modules.exclude?(ActiveMerchant::Billing::PagarmeGatewayDecorator)
  ActiveMerchant::Billing::PagarmeGateway.prepend(ActiveMerchant::Billing::PagarmeGatewayDecorator)
end
