module SpreeGateway
  module UserDecorator
    def full_name
      return firstname if lastname.blank?

      "#{firstname} #{lastname}"
    end
  end
end

%i[
  cpf
  firstname
  lastname
  phone
].each do |attr|
  Spree::PermittedAttributes.user_attributes.push attr unless Spree::PermittedAttributes.user_attributes.include? attr
end

::Spree::User.prepend(::SpreeGateway::UserDecorator)