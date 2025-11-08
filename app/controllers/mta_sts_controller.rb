# frozen_string_literal: true

class MtaStsController < ApplicationController

  skip_before_action :login_required
  skip_before_action :set_timezone

  layout false
  protect_from_forgery with: :null_session

  # GET /.well-known/mta-sts.txt
  # Serve la policy MTA-STS per il dominio richiesto
  def policy
    domain_name = extract_domain_from_host

    Rails.logger.info "MTA-STS policy request - Host: #{request.host}, Extracted domain: #{domain_name}"

    unless domain_name.present?
      Rails.logger.warn "MTA-STS policy request failed - Invalid domain from host: #{request.host}"
      render plain: "Invalid domain", status: :not_found
      return
    end

    # Cerca il dominio nel database
    # Il dominio deve essere verificato e avere MTA-STS abilitato
    # La ricerca è case-insensitive per il nome del dominio
    domain = Domain.verified.where(mta_sts_enabled: true)
                     .where("LOWER(name) = ?", domain_name.downcase)
                     .first

    unless domain
      Rails.logger.warn "MTA-STS policy request failed - Domain not found or not enabled: #{domain_name}"
      render plain: "MTA-STS policy not found", status: :not_found
      return
    end

    policy_content = domain.mta_sts_policy_content

    unless policy_content
      Rails.logger.error "MTA-STS policy request failed - No policy content for domain: #{domain_name}"
      render plain: "MTA-STS policy not configured", status: :not_found
      return
    end

    # Serve la policy come plain text
    response.headers["Content-Type"] = "text/plain; charset=utf-8"
    response.headers["Cache-Control"] = "max-age=#{domain.mta_sts_max_age || 86400}"

    Rails.logger.info "MTA-STS policy served successfully for domain: #{domain_name}"
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

