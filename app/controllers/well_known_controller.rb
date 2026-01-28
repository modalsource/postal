# frozen_string_literal: true

class WellKnownController < ApplicationController

  layout false
  protect_from_forgery with: :null_session

  skip_before_action :login_required
  skip_before_action :set_timezone

  def jwks
    render json: JWT::JWK::Set.new(Postal.signer.jwk).export.to_json
  end

end
