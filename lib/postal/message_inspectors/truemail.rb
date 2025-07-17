# frozen_string_literal: true

require 'net/http'
require 'json'
require 'timeout'

module Postal
  module MessageInspectors
    class Truemail < MessageInspector

      def inspect_message(inspection)
        # Truemail valida gli indirizzi email, non il contenuto del messaggio
        # Estraiamo l'indirizzo To dal messaggio
        message = inspection.message
        to_address = extract_to_address(message)

        return unless to_address

        begin
          validation_result = validate_email(to_address)

          if validation_result[:success]
            inspection.validation_failed = false
            inspection.validation_message = "Email address validation passed"
            inspection.spam_checks << SpamCheck.new("TRUEMAIL_VALID", 0, "Email address is valid")
          else
            inspection.validation_failed = true
            inspection.validation_message = "Email address validation failed: #{validation_result[:errors]&.join(', ')}"
            inspection.spam_checks << SpamCheck.new("TRUEMAIL_INVALID", 10, validation_result[:errors]&.join(', ') || "Invalid email address")
          end
        rescue Timeout::Error
          inspection.validation_failed = false
          inspection.validation_message = "Timed out validating email address"
          inspection.spam_checks << SpamCheck.new("TRUEMAIL_TIMEOUT", 0, "Email validation timed out")
        rescue StandardError => e
          logger.error "Error talking to Truemail API: #{e.class} (#{e.message})"
          logger.error e.backtrace[0, 5]
          inspection.validation_failed = false
          inspection.validation_message = "Error when validating email address"
          inspection.spam_checks << SpamCheck.new("TRUEMAIL_ERROR", 0, "Error validating email address")
        end
      end

      private

      def extract_to_address(message)
        # Estrae l'indirizzo To dal messaggio
        if message.respond_to?(:to)
          message.to&.first
        elsif message.respond_to?(:raw_message)
          # Parsing manuale dell'header To dal raw message
          raw = message.raw_message
          if raw =~ /^To:\s*(.+)$/mi
            $1.strip
          end
        end
      end

      def validate_email(email)
        uri = URI("#{@config.url}/validate")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = @config.timeout || 10

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request.body = { email: email }.to_json

        Timeout.timeout(@config.timeout || 10) do
          response = http.request(request)

          if response.code == '200'
            result = JSON.parse(response.body)
            {
              success: result['result'] == 'valid',
              errors: result['errors']
            }
          else
            {
              success: false,
              errors: ["HTTP #{response.code}: #{response.message}"]
            }
          end
        end
      end

    end
  end
end
