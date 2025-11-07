# frozen_string_literal: true

class MtaStsController < ApplicationController

  layout false

  skip_before_action :set_browser_id
  skip_before_action :login_required
  skip_before_action :set_timezone
  skip_before_action :verify_authenticity_token

  # GET /.well-known/mta-sts.txt
  # Serve la policy MTA-STS per il dominio richiesto
  def policy
    domain_name = extract_domain_from_host

    unless domain_name
      render plain: "Invalid domain", status: :not_found
      return
    end

    # Cerca il dominio nel database
    # Il dominio deve essere verificato e avere MTA-STS abilitato
    domain = Domain.verified.find_by(name: domain_name, mta_sts_enabled: true)

    unless domain
      render plain: "MTA-STS policy not found", status: :not_found
      return
    end

    policy_content = domain.mta_sts_policy_content

    unless policy_content
      render plain: "MTA-STS policy not configured", status: :not_found
      return
    end

    # Serve la policy come plain text
    response.headers["Content-Type"] = "text/plain; charset=utf-8"
    response.headers["Cache-Control"] = "max-age=#{domain.mta_sts_max_age || 86400}"

    render plain: policy_content
  end

  private

  def extract_domain_from_host
    host = request.host

    # Rimuove il prefisso mta-sts. se presente
    # es: mta-sts.example.com -> example.com
    if host.start_with?("mta-sts.")
      host.sub(/\Amta-sts\./, "")
    else
      host
    end
  end

end

