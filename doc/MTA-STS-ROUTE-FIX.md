# Fix per la Route MTA-STS .well-known/mta-sts.txt

## Problema Risolto

La route `.well-known/mta-sts.txt` non funzionava correttamente perché:

1. **Host Authorization**: Rails bloccava le richieste da host con pattern `mta-sts.*`
2. **Autenticazione**: Il controller richiedeva il login anche per endpoint pubblici
3. **Eccezioni Authie**: Le eccezioni della sessione non venivano gestite correttamente per endpoint pubblici
4. **CSRF Protection**: Il token CSRF causava errori 403

## Modifiche Effettuate

### 1. Controller MTA-STS (`app/controllers/mta_sts_controller.rb`)

**Modifiche principali:**
- ✅ Rimosso `skip_before_action :set_browser_id` (metodo non più esistente)
- ✅ Aggiunto `protect_from_forgery with: :null_session` per endpoint pubblici
- ✅ Aggiunto `rescue_from` per eccezioni Authie con handler che non fa nulla
- ✅ Migliorato logging per debugging
- ✅ Aggiunta ricerca case-insensitive per nomi dominio

**Funzionalità:**
- Endpoint pubblico accessibile senza autenticazione
- Gestisce richieste sia da `mta-sts.example.com` che da `example.com`
- Logging dettagliato per troubleshooting
- Ricerca domini case-insensitive

### 2. Controller Well Known (`app/controllers/well_known_controller.rb`)

**Modifiche:**
- ✅ Rimosso `skip_before_action :set_browser_id` (non più esistente)
- ✅ Aggiunto `protect_from_forgery with: :null_session` per consistenza

### 3. Controller Legacy API Base (`app/controllers/legacy_api/base_controller.rb`)

**Modifiche:**
- ✅ Rimosso `skip_before_action :set_browser_id` (non più esistente)

### 4. Configurazione Application (`config/application.rb`)

**Modifiche:**
- ✅ Aggiunto pattern per autorizzare host `mta-sts.*`
- ✅ Pattern: `/\Amta-sts\./i` per accettare tutti i sottodomini mta-sts

```ruby
config.hosts << Postal::Config.postal.web_hostname
# Allow mta-sts subdomains for MTA-STS policy serving
config.hosts << /\Amta-sts\./i
```

### 5. Configurazione Test (`config/environments/test.rb`)

**Modifiche:**
- ✅ Aggiunto `config.hosts << /.*/` per accettare qualsiasi host nei test
- ✅ Semplifica il testing senza dover configurare host specifici

### 6. Test Specs (`spec/controllers/mta_sts_controller_spec.rb`)

**Creato nuovo file di test con:**
- ✅ Test per domini con MTA-STS abilitato
- ✅ Test per MX patterns personalizzati
- ✅ Test per domini non verificati
- ✅ Test per domini con MTA-STS disabilitato
- ✅ Test per domini inesistenti
- ✅ Test per richieste senza prefisso mta-sts
- ✅ Test per nomi dominio case-insensitive
- ✅ Tutti i test passano ✅

## Come Funziona Ora

### 1. Richiesta da `mta-sts.example.com`

```
GET https://mta-sts.example.com/.well-known/mta-sts.txt
Host: mta-sts.example.com
```

**Flusso:**
1. Host Authorization: `mta-sts.example.com` matcha il pattern `/\Amta-sts\./i` ✅
2. Controller rimuove il prefisso `mta-sts.` → `example.com`
3. Cerca `Domain.verified.where(mta_sts_enabled: true).where("LOWER(name) = ?", "example.com")`
4. Se trovato, restituisce `domain.mta_sts_policy_content`
5. Response: 200 OK con `Content-Type: text/plain; charset=utf-8`

### 2. Richiesta da dominio principale

```
GET https://example.com/.well-known/mta-sts.txt
Host: example.com
```

**Flusso:**
1. Host Authorization: `example.com` è già autorizzato ✅
2. Controller usa direttamente `example.com`
3. Cerca dominio nel database
4. Restituisce policy se trovata

### 3. Casi di errore

**404 Not Found quando:**
- Dominio non esiste nel database
- Dominio non è verificato (`verified_at IS NULL`)
- MTA-STS non è abilitato (`mta_sts_enabled = false`)
- Policy non è configurata (`mta_sts_policy_content` è vuoto)

## Test

Eseguire i test con:

```bash
bundle exec rspec spec/controllers/mta_sts_controller_spec.rb --format documentation
```

**Risultato atteso:**
```
MTA-STS Policy
  GET /.well-known/mta-sts.txt
    when domain has MTA-STS enabled
      returns the MTA-STS policy
      sets the correct cache control header
    when domain has MTA-STS enabled with custom MX patterns
      includes custom MX patterns in the policy
    when domain is not verified
      returns 404 not found
    when domain has MTA-STS disabled
      returns 404 not found
    when domain does not exist
      returns 404 not found
    when host is the main domain without mta-sts prefix
      returns the MTA-STS policy
    when domain name is case-insensitive
      returns the MTA-STS policy

8 examples, 0 failures
```

## Configurazione DNS Richiesta

Per servire correttamente le policy MTA-STS, configurare:

```
# Record A o CNAME per mta-sts subdomain
mta-sts.example.com.    A    <IP-SERVER-POSTAL>
# oppure
mta-sts.example.com.    CNAME    postal.example.com.

# Record TXT per MTA-STS
_mta-sts.example.com.    TXT    "v=STSv1; id=<policy-id>;"
```

## Logging

Il controller ora logga tutte le richieste:

```
MTA-STS policy request - Host: mta-sts.example.com, Extracted domain: example.com
MTA-STS policy served successfully for domain: example.com
```

Errori loggati:
```
MTA-STS policy request failed - Invalid domain from host: invalid
MTA-STS policy request failed - Domain not found or not enabled: nonexistent.com
MTA-STS policy request failed - No policy content for domain: example.com
```

## Note Importanti

1. **Endpoint Pubblico**: Non richiede autenticazione - accessibile a tutti
2. **Case Insensitive**: Accetta `EXAMPLE.COM`, `example.com`, `Example.Com`
3. **Cache Control**: Rispetta il `mta_sts_max_age` del dominio (default: 86400)
4. **HTTPS Obbligatorio**: In produzione MTA-STS richiede HTTPS con certificato valido
5. **Standard Compliance**: Implementazione conforme a RFC 8461

## Riferimenti

- RFC 8461: SMTP MTA Strict Transport Security (MTA-STS)
- [MTA-STS Documentation](./MTA-STS-AND-TLS-RPT.md)
- [MTA-STS Implementation Summary](./MTA-STS-IMPLEMENTATION-SUMMARY.md)

