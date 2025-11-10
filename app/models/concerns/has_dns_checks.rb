# frozen_string_literal: true

require "resolv"

module HasDNSChecks

  def dns_ok?
    spf_status == "OK" && dkim_status == "OK" && %w[OK Missing].include?(mx_status) && %w[OK Missing].include?(return_path_status) && %w[OK Missing].include?(dmarc_status)
  end

  def dns_checked?
    spf_status.present?
  end

  def check_dns(source = :manual)
    check_spf_record
    check_dkim_record
    check_mx_records
    check_return_path_record
    check_dmarc_record
    check_mta_sts_record if respond_to?(:mta_sts_enabled)
    check_tls_rpt_record if respond_to?(:tls_rpt_enabled)
    self.dns_checked_at = Time.now
    save!
    if source == :auto && !dns_ok? && owner.is_a?(Server)
      WebhookRequest.trigger(owner, "DomainDNSError", {
        server: owner.webhook_hash,
        domain: name,
        uuid: uuid,
        dns_checked_at: dns_checked_at.to_f,
        spf_status: spf_status,
        spf_error: spf_error,
        dkim_status: dkim_status,
        dkim_error: dkim_error,
        mx_status: mx_status,
        mx_error: mx_error,
        return_path_status: return_path_status,
        return_path_error: return_path_error,
        dmarc_status: dmarc_status,
        dmarc_error: dmarc_error
      })
    end
    dns_ok?
  end

  #
  # SPF
  #

  def check_spf_record
    result = resolver.txt(name)
    spf_records = result.grep(/\Av=spf1/)
    if spf_records.empty?
      self.spf_status = "Missing"
      self.spf_error = "No SPF record exists for this domain"
    else
      suitable_spf_records = spf_records.grep(/include:\s*#{Regexp.escape(Postal::Config.dns.spf_include)}/)
      if suitable_spf_records.empty?
        self.spf_status = "Invalid"
        self.spf_error = "An SPF record exists but it doesn't include #{Postal::Config.dns.spf_include}"
        false
      else
        self.spf_status = "OK"
        self.spf_error = nil
        true
      end
    end
  end

  def check_spf_record!
    check_spf_record
    save!
  end

  #
  # DKIM
  #

  def check_dkim_record
    domain = "#{dkim_record_name}.#{name}"
    check_dkim_record_recursive(domain, domain, 0)
  end

  def check_dkim_record_recursive(originaldomain, domain, level)
    records = resolver.txt(domain)
    if records.empty?
      records = resolver.cname(domain)
      if (!records.empty? && records.size == 1 && level < 10)
        return check_dkim_record_recursive(originaldomain, records.first, level+1)
      else
        self.dkim_status = "Missing"
        self.dkim_error = "No TXT records were returned for #{originaldomain}"
      end
    else
      sanitised_dkim_record = records.first.strip.ends_with?(";") ? records.first.strip : "#{records.first.strip};"
      if records.size > 1
        self.dkim_status = "Invalid"
        self.dkim_error = "There are #{records.size} records for at #{originaldomain}. There should only be one."
      elsif sanitised_dkim_record != dkim_record
        self.dkim_status = "Invalid"
        self.dkim_error = "The DKIM record at #{originaldomain} does not match the record we have provided. Please check it has been copied correctly."
      else
        self.dkim_status = "OK"
        self.dkim_error = nil
        true
      end
    end
  end

  def check_dkim_record!
    check_dkim_record
    save!
  end

  #
  # MX
  #

  def check_mx_records
    records = resolver.mx(name).map(&:last)
    if records.empty?
      self.mx_status = "Missing"
      self.mx_error = "There are no MX records for #{name}"
    else
      missing_records = Postal::Config.dns.mx_records.dup - records.map { |r| r.to_s.downcase }
      if missing_records.empty?
        self.mx_status = "OK"
        self.mx_error = nil
      elsif missing_records.size == Postal::Config.dns.mx_records.size
        self.mx_status = "Missing"
        self.mx_error = "You have MX records but none of them point to us."
      else
        self.mx_status = "Invalid"
        self.mx_error = "MX #{missing_records.size == 1 ? 'record' : 'records'} for #{missing_records.to_sentence} are missing and are required."
      end
    end
  end

  def check_mx_records!
    check_mx_records
    save!
  end

  #
  # Return Path
  #

  def check_return_path_record
    records = resolver.cname(return_path_domain)
    if records.empty?
      self.return_path_status = "Missing"
      self.return_path_error = "There is no return path record at #{return_path_domain}"
    elsif records.size == 1 && records.first == Postal::Config.dns.return_path_domain
      self.return_path_status = "OK"
      self.return_path_error = nil
    else
      self.return_path_status = "Invalid"
      self.return_path_error = "There is a CNAME record at #{return_path_domain} but it points to #{records.first} which is incorrect. It should point to #{Postal::Config.dns.return_path_domain}."
    end
  end

  def check_return_path_record!
    check_return_path_record
    save!
  end

  #
  # DMARC
  #

  def check_dmarc_record
    # Only check DMARC if a preferred DNS entry is configured
    if Postal::Config.dns.dmarc_preferred_dns_entry.present?
      dmarc_domain = "_dmarc.#{name}"
      records = resolver.txt(dmarc_domain)
      
      if records.empty?
        self.dmarc_status = "Missing"
        self.dmarc_error = "No DMARC record exists for this domain at #{dmarc_domain}"
      else
        dmarc_records = records.grep(/\Av=DMARC1/)
        if dmarc_records.empty?
          self.dmarc_status = "Invalid"
          self.dmarc_error = "A TXT record exists at #{dmarc_domain} but it doesn't contain a valid DMARC record (should start with v=DMARC1)"
        elsif dmarc_records.first.strip == Postal::Config.dns.dmarc_preferred_dns_entry.strip
          self.dmarc_status = "OK"
          self.dmarc_error = nil
        else
          self.dmarc_status = "Invalid"
          self.dmarc_error = "The DMARC record at #{dmarc_domain} does not match the preferred record. Please check it has been configured correctly."
        end
      end
    else
      # If no preferred entry is configured, mark as Missing (not checked)
      self.dmarc_status = "Missing"
      self.dmarc_error = nil
    end
  end

  def check_dmarc_record!
    check_dmarc_record

  #
  # MTA-STS
  #

  def check_mta_sts_record
    return unless respond_to?(:mta_sts_enabled) && mta_sts_enabled

    # Check DNS TXT record
    records = resolver.txt(mta_sts_record_name)
    if records.empty?
      self.mta_sts_status = "Missing"
      self.mta_sts_error = "No TXT record exists at #{mta_sts_record_name}"
      return false
    end

    expected_prefix = "v=STSv1; id="
    matching_records = records.select { |r| r.strip.start_with?(expected_prefix) }

    if matching_records.empty?
      self.mta_sts_status = "Invalid"
      self.mta_sts_error = "The TXT record at #{mta_sts_record_name} doesn't contain a valid MTA-STS policy"
      return false
    elsif matching_records.size > 1
      self.mta_sts_status = "Invalid"
      self.mta_sts_error = "Multiple MTA-STS records found at #{mta_sts_record_name}. There should only be one."
      return false
    end

    # Check HTTPS policy file accessibility
    policy_check_result = check_mta_sts_policy_file
    unless policy_check_result[:success]
      self.mta_sts_status = "Invalid"
      self.mta_sts_error = policy_check_result[:error]
      return false
    end

    self.mta_sts_status = "OK"
    self.mta_sts_error = nil
    true
  end

  def check_mta_sts_policy_file
    require 'net/http'
    require 'uri'

    url = "https://mta-sts.#{name}/.well-known/mta-sts.txt"

    begin
      uri = URI.parse(url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = 10
      http.read_timeout = 10

      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)

      if response.code != '200'
        error_message = "Policy file returned HTTP #{response.code}. Expected 200. URL: #{url}"

        # Add helpful hints for common errors
        if response.code == '403'
          error_message += "\n\nThis usually means the endpoint is protected by HTTP authentication or firewall rules. "
          error_message += "Make sure /.well-known/mta-sts.txt is publicly accessible without authentication."
        elsif response.code == '404'
          error_message += "\n\nThe policy file was not found. Verify that your web server is correctly routing requests to the Postal application."
        elsif response.code.to_i >= 500
          error_message += "\n\nThe server encountered an error. Check your application logs for more details."
        end

        return {
          success: false,
          error: error_message
        }
      end

      # Validate policy content
      policy_body = response.body

      unless policy_body.include?('version: STSv1')
        return {
          success: false,
          error: "Policy file doesn't contain 'version: STSv1'. URL: #{url}"
        }
      end

      unless policy_body.match?(/mode:\s*(testing|enforce|none)/)
        return {
          success: false,
          error: "Policy file doesn't contain a valid mode (testing, enforce, or none). URL: #{url}"
        }
      end

      unless policy_body.match?(/max_age:\s*\d+/)
        return {
          success: false,
          error: "Policy file doesn't contain a valid max_age value. URL: #{url}"
        }
      end

      { success: true }

    rescue OpenSSL::SSL::SSLError => e
      {
        success: false,
        error: "SSL certificate error for #{url}: #{e.message}"
      }
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      {
        success: false,
        error: "Timeout while fetching policy file from #{url}: #{e.message}"
      }
    rescue StandardError => e
      {
        success: false,
        error: "Error fetching policy file from #{url}: #{e.message}"
      }
    end
  end

  def check_mta_sts_record!
    check_mta_sts_record
    save!
  end

  #
  # TLS-RPT
  #

  def check_tls_rpt_record
    return unless respond_to?(:tls_rpt_enabled) && tls_rpt_enabled

    records = resolver.txt(tls_rpt_record_name)
    if records.empty?
      self.tls_rpt_status = "Missing"
      self.tls_rpt_error = "No TXT record exists at #{tls_rpt_record_name}"
    else
      expected_prefix = "v=TLSRPTv1;"
      matching_records = records.select { |r| r.strip.start_with?(expected_prefix) }

      if matching_records.empty?
        self.tls_rpt_status = "Invalid"
        self.tls_rpt_error = "The TXT record at #{tls_rpt_record_name} doesn't contain a valid TLS-RPT policy"
      elsif matching_records.size > 1
        self.tls_rpt_status = "Invalid"
        self.tls_rpt_error = "Multiple TLS-RPT records found at #{tls_rpt_record_name}. There should only be one."
      elsif !matching_records.first.include?("rua=")
        self.tls_rpt_status = "Invalid"
        self.tls_rpt_error = "The TLS-RPT record must include a 'rua=' directive"
      else
        self.tls_rpt_status = "OK"
        self.tls_rpt_error = nil
        true
      end
    end
  end

  def check_tls_rpt_record!
    check_tls_rpt_record
    save!
  end

end

# -*- SkipSchemaAnnotations
