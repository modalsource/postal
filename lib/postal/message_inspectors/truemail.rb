# frozen_string_literal: true

require 'truemail/client'

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
        client = create_client

        Timeout.timeout(@config.timeout || 10) do
          response = client.validate(email: email)

          {
            success: response.dig('result', 'success') == true,
            errors: extract_errors(response)
          }
        end
      end

      def create_client
        configuration = { 
          host: @config.host,
          port: @config.port || 9292,
          secure_connection: @config.ssl || false
        }
        
        configuration[:token] = @config.token if @config.token.present?

        ::Truemail::Client.configure do |config|
          config.host = configuration[:host]
          config.port = configuration[:port]
          config.secure_connection = configuration[:secure_connection]
          config.token = configuration[:token] if configuration[:token]
        end

        ::Truemail::Client.new
      end

      def extract_errors(response)
        errors = []
        
        if response.dig('result', 'success') == false
          errors << (response.dig('result', 'errors') || response.dig('errors') || ['Validation failed'])
        end

        errors.flatten
      end

    end
  end
end
