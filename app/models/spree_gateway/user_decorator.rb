module SpreeGateway
  module UserDecorator
    def full_name
      name
    end
  end
end

%i[
  document_type
  phone
].each do |attr|
  Spree::PermittedAttributes.user_attributes.push attr unless Spree::PermittedAttributes.user_attributes.include? attr
end

::Spree::User.prepend(::SpreeGateway::UserDecorator)