# frozen_string_literal: true

module IPBlacklist
  # Parses SMTP response codes and messages to detect blacklist-related rejections.
  # Supports pattern matching for:
  # - Gmail: reputation-based throttling and blocking
  # - Outlook/Hotmail: IP blocking and reputation issues
  # - Yahoo: spam filtering and IP blocking
  # - Generic DNSBL patterns: Spamhaus, Barracuda, SORBS, SpamCop, etc.
  #
  # @example Parse an SMTP error message
  #   result = IPBlacklist::SmtpResponseParser.parse(
  #     "554 Service unavailable; Client host [192.0.2.1] blocked using zen.spamhaus.org",
  #     "554"
  #   )
  #   result[:blacklist_detected] # => true
  #   result[:blacklist_source] # => "spamhaus_zen"
  #   result[:severity] # => "high"
  #
  class SmtpResponseParser

    # SMTP code categories
    SOFT_BOUNCE_CODES = %w[421 450 451 452].freeze
    HARD_BOUNCE_CODES = %w[550 551 552 553 554].freeze

    # Generic DNSBL pattern mappings
    DNSBL_PATTERNS = {
      /zen\.spamhaus\.org/i => "spamhaus_zen",
      /sbl\.spamhaus\.org/i => "spamhaus_sbl",
      /xbl\.spamhaus\.org/i => "spamhaus_xbl",
      /pbl\.spamhaus\.org/i => "spamhaus_pbl",
      /bl\.spamcop\.net/i => "spamcop",
      /b\.barracudacentral\.org/i => "barracuda",
      /dnsbl\.sorbs\.net/i => "sorbs",
      /psbl\.surriel\.com/i => "psbl",
      /uribl\.com/i => "uribl",
      /multi\.surbl\.org/i => "surbl",
      /bl\.mailspike\.net/i => "mailspike",
      /dnsbl/i => "generic_dnsbl",
      /blacklist/i => "generic_blacklist",
      /blocklist/i => "generic_blocklist",
      /\bRBL\b/i => "generic_rbl"
    }.freeze

    # Gmail-specific patterns
    GMAIL_PATTERNS = [
      {
        regex: /421[- ]4\.7\.0.*rate limit.*exceeded/i,
        source: "gmail_rate_limit",
        severity: "medium",
        description: "Gmail rate limiting due to suspicious activity or low reputation"
      },
      {
        regex: /421[- ]4\.7\.0.*Try again later/i,
        source: "gmail_temporary_block",
        severity: "high",
        description: "Gmail temporary block - likely reputation issue"
      },
      {
        regex: /550[- ]5\.7\.1.*Our system has detected.*suspicious/i,
        source: "gmail_suspicious_activity",
        severity: "high",
        description: "Gmail detected suspicious activity"
      },
      {
        regex: /550[- ]5\.7\.1.*email.*blocked.*policy/i,
        source: "gmail_policy_block",
        severity: "high",
        description: "Gmail policy-based blocking"
      },
      {
        regex: /550[- ]5\.7\.26.*message.*not pass authentication/i,
        source: "gmail_authentication_failure",
        severity: "medium",
        description: "Gmail SPF/DKIM/DMARC authentication failure"
      },
    ].freeze

    # Outlook/Hotmail-specific patterns
    OUTLOOK_PATTERNS = [
      {
        regex: /550[- ]5\.7\.1.*Service unavailable.*Client host.*rejected/i,
        source: "outlook_ip_blocked",
        severity: "high",
        description: "Outlook/Hotmail IP blocking"
      },
      {
        regex: /550[- ]5\.7\.1.*blocked.*IP reputation/i,
        source: "outlook_reputation_block",
        severity: "high",
        description: "Outlook IP reputation blocking"
      },
      {
        regex: /550[- ].*\(BAY\d+\).*block list.*DNSBL/i,
        source: "outlook_dnsbl_block",
        severity: "high",
        description: "Outlook DNSBL-based blocking"
      },
      {
        regex: /421[- ]4\.3\.2.*temporarily deferred/i,
        source: "outlook_temporary_defer",
        severity: "medium",
        description: "Outlook temporary deferral - possible reputation issue"
      },
    ].freeze

    # Yahoo-specific patterns
    YAHOO_PATTERNS = [
      {
        regex: /421[- ]4\.7\.0.*\[TS\d+\]/i,
        source: "yahoo_throttle",
        severity: "medium",
        description: "Yahoo throttling due to volume or reputation"
      },
      {
        regex: /554[- ]5\.7\.9.*Message not accepted for policy reasons/i,
        source: "yahoo_policy_block",
        severity: "high",
        description: "Yahoo policy-based blocking"
      },
      {
        regex: /553[- ].*spam.*blocked/i,
        source: "yahoo_spam_block",
        severity: "high",
        description: "Yahoo spam filtering block"
      },
    ].freeze

    # Parse SMTP response message and code
    #
    # @param message [String] The SMTP error message
    # @param smtp_code [String] The SMTP response code (e.g., "550", "421")
    # @return [Hash] Parsed result with detection info
    #   - :blacklist_detected [Boolean] Whether a blacklist was detected
    #   - :bounce_type [String] "soft" or "hard"
    #   - :blacklist_source [String, nil] Identified blacklist source
    #   - :severity [String] "low", "medium", "high"
    #   - :description [String] Human-readable description
    #   - :suggested_action [String] Recommended action
    #   - :smtp_code_category [String] Code category
    #
    def self.parse(message, smtp_code)
      return default_result(smtp_code) if message.blank?

      result = {
        blacklist_detected: false,
        bounce_type: determine_bounce_type(smtp_code),
        blacklist_source: nil,
        severity: "low",
        description: "Generic SMTP rejection",
        suggested_action: "monitor",
        smtp_code_category: categorize_smtp_code(smtp_code),
        raw_message: message
      }

      # Check for provider-specific patterns first (most specific)
      # then generic DNSBL patterns (fallback)
      check_gmail_patterns(message, result) ||
        check_outlook_patterns(message, result) ||
        check_yahoo_patterns(message, result) ||
        check_generic_dnsbl_patterns(message, result)

      # Determine suggested action based on severity and bounce type
      result[:suggested_action] = determine_suggested_action(result)

      result
    end

    # @private
    def self.default_result(smtp_code)
      {
        blacklist_detected: false,
        bounce_type: determine_bounce_type(smtp_code),
        blacklist_source: nil,
        severity: "low",
        description: "Generic SMTP rejection",
        suggested_action: "monitor",
        smtp_code_category: categorize_smtp_code(smtp_code),
        raw_message: nil
      }
    end

    # @private
    def self.determine_bounce_type(smtp_code)
      return "hard" if HARD_BOUNCE_CODES.include?(smtp_code)
      return "soft" if SOFT_BOUNCE_CODES.include?(smtp_code)

      # Default based on first digit
      smtp_code.to_s[0] == "5" ? "hard" : "soft"
    end

    # @private
    def self.categorize_smtp_code(smtp_code)
      case smtp_code.to_s[0]
      when "2"
        "success"
      when "4"
        "temporary_failure"
      when "5"
        "permanent_failure"
      else
        "unknown"
      end
    end

    # @private
    def self.check_gmail_patterns(message, result)
      GMAIL_PATTERNS.each do |pattern|
        next unless message =~ pattern[:regex]

        result[:blacklist_detected] = true
        result[:blacklist_source] = pattern[:source]
        result[:severity] = pattern[:severity]
        result[:description] = pattern[:description]
        return true
      end
      false
    end

    # @private
    def self.check_outlook_patterns(message, result)
      OUTLOOK_PATTERNS.each do |pattern|
        next unless message =~ pattern[:regex]

        result[:blacklist_detected] = true
        result[:blacklist_source] = pattern[:source]
        result[:severity] = pattern[:severity]
        result[:description] = pattern[:description]
        return true
      end
      false
    end

    # @private
    def self.check_yahoo_patterns(message, result)
      YAHOO_PATTERNS.each do |pattern|
        next unless message =~ pattern[:regex]

        result[:blacklist_detected] = true
        result[:blacklist_source] = pattern[:source]
        result[:severity] = pattern[:severity]
        result[:description] = pattern[:description]
        return true
      end
      false
    end

    # @private
    def self.check_generic_dnsbl_patterns(message, result)
      DNSBL_PATTERNS.each do |pattern, source|
        next unless message =~ pattern

        result[:blacklist_detected] = true
        result[:blacklist_source] = source
        result[:severity] = "high"
        result[:description] = "IP listed on #{source.gsub('_', ' ').titleize}"
        return true
      end
      false
    end

    # @private
    def self.determine_suggested_action(result)
      return "monitor" unless result[:blacklist_detected]

      case result[:severity]
      when "high"
        result[:bounce_type] == "hard" ? "pause_immediately" : "track_soft_bounces"
      when "medium"
        result[:bounce_type] == "hard" ? "pause_after_threshold" : "monitor_closely"
      else
        "monitor"
      end
    end

  end
end
