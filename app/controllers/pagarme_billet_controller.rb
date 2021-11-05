# frozen_string_literal: true

class PagarmeBilletController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false

  def post_back
    @billet = Spree::PagarmeBillet.find(params[:id])
    if params[:token] && (@billet.token == params[:token]) && (params[:desired_status] == 'paid')
      @billet.payment.complete
    else
      render json: {}, status: :not_found
    end
  end
end
