#!/usr/bin/env ruby
# frozen_string_literal: true

# Script per testare l'endpoint MTA-STS localmente
# Usage: ruby script/test_mta_sts_endpoint.rb [domain_name]

require_relative '../config/environment'

domain_name = ARGV[0] || 'nurtigo.io'

puts "=" * 80
puts "Test MTA-STS Endpoint per #{domain_name}"
puts "=" * 80
puts

# Trova il dominio nel database
domain = Domain.verified.where(mta_sts_enabled: true)
               .where("LOWER(name) = ?", domain_name.downcase)
               .first

unless domain
  puts "❌ Dominio non trovato o MTA-STS non abilitato"
  puts
  puts "Verifica che:"
  puts "  1. Il dominio '#{domain_name}' esista nel database"
  puts "  2. Il dominio sia verificato (verified_at non NULL)"
  puts "  3. MTA-STS sia abilitato (mta_sts_enabled = true)"
  puts

  # Mostra informazioni sul dominio se esiste
  any_domain = Domain.where("LOWER(name) = ?", domain_name.downcase).first
  if any_domain
    puts "Dominio trovato ma con queste proprietà:"
    puts "  - Verificato: #{any_domain.verified? ? '✅' : '❌'}"
    puts "  - MTA-STS abilitato: #{any_domain.mta_sts_enabled ? '✅' : '❌'}"
  else
    puts "Nessun dominio trovato con nome '#{domain_name}'"
    puts
    puts "Domini disponibili:"
    Domain.all.each do |d|
      puts "  - #{d.name} (verificato: #{d.verified?}, MTA-STS: #{d.mta_sts_enabled})"
    end
  end

  exit 1
end

puts "✅ Dominio trovato: #{domain.name}"
puts "   - Verificato: #{domain.verified_at}"
puts "   - MTA-STS Mode: #{domain.mta_sts_mode}"
puts "   - MTA-STS Max Age: #{domain.mta_sts_max_age}"
puts

# Testa la generazione della policy
puts "-" * 80
puts "Policy Content:"
puts "-" * 80
policy_content = domain.mta_sts_policy_content
if policy_content
  puts policy_content
else
  puts "❌ Nessuna policy generata!"
end
puts

# Simula una richiesta HTTP al controller
puts "-" * 80
puts "Test della richiesta HTTP (simulata):"
puts "-" * 80

require 'rack/mock'

# Test con prefisso mta-sts
test_hosts = [
  "mta-sts.#{domain_name}",
  domain_name
]

test_hosts.each do |host|
  puts "\nTest con Host: #{host}"
  env = Rack::MockRequest.env_for(
    "https://#{host}/.well-known/mta-sts.txt",
    'HTTP_HOST' => host
  )

  status, headers, body = Rails.application.call(env)

  puts "  Status: #{status}"
  puts "  Content-Type: #{headers['Content-Type']}"
  puts "  Cache-Control: #{headers['Cache-Control']}"

  body_content = if body.respond_to?(:body)
                   body.body
                 elsif body.is_a?(Array)
                   body.join
                 else
                   body.to_s
                 end

  if status == 200
    puts "  ✅ Successo!"
    puts "  Body preview: #{body_content[0..100]}..."
  else
    puts "  ❌ Errore!"
    puts "  Body: #{body_content}"
  end
end

puts
puts "=" * 80
puts "Test completato!"
puts "=" * 80
puts
puts "NOTA: Se il test locale funziona ma il check dall'UI fallisce con 403,"
puts "      il problema è nel tuo reverse proxy (nginx/apache/caddy)."
puts "      Consulta doc/MTA-STS-PUBLIC-ACCESS.md per la configurazione."
puts

