# Implementazione MTA-STS e TLS-RPT in Postal

## Panoramica

Questa implementazione aggiunge il supporto per MTA-STS (SMTP MTA Strict Transport Security) e TLS-RPT (TLS Reporting) a Postal, migliorando la sicurezza delle comunicazioni email.

## Componenti Implementati

### 1. Database Migration
**File:** `db/migrate/20251107000001_add_mta_sts_and_tls_rpt_to_domains.rb`

Aggiunge i seguenti campi alla tabella `domains`:
- `mta_sts_enabled` (boolean): Abilita/disabilita MTA-STS
- `mta_sts_mode` (string): Modalità policy (testing, enforce, none)
- `mta_sts_max_age` (integer): Durata cache della policy in secondi
- `mta_sts_mx_patterns` (text): Pattern MX personalizzati (uno per riga)
- `mta_sts_status` (string): Stato verifica DNS
- `mta_sts_error` (string): Messaggio errore verifica DNS
- `tls_rpt_enabled` (boolean): Abilita/disabilita TLS-RPT
- `tls_rpt_email` (string): Email per ricevere report TLS
- `tls_rpt_status` (string): Stato verifica DNS
- `tls_rpt_error` (string): Messaggio errore verifica DNS

### 2. Model Domain
**File:** `app/models/domain.rb`

#### Metodi MTA-STS:
- `mta_sts_record_name`: Nome record DNS (_mta-sts.domain.com)
- `mta_sts_record_value`: Valore del record DNS TXT
- `mta_sts_policy_id`: ID univoco della policy (basato su hash della configurazione)
- `mta_sts_policy_content`: Contenuto del file policy in formato testo
- `default_mta_sts_mx_patterns`: Pattern MX di default da configurazione Postal

#### Metodi TLS-RPT:
- `tls_rpt_record_name`: Nome record DNS (_smtp._tls.domain.com)
- `tls_rpt_record_value`: Valore del record DNS TXT
- `default_tls_rpt_email`: Email di default per report

### 3. Concern HasDNSChecks
**File:** `app/models/concerns/has_dns_checks.rb`

#### Metodi aggiunti:
- `check_mta_sts_record`: Verifica il record DNS MTA-STS e la disponibilità HTTPS del file policy
- `check_mta_sts_record!`: Verifica e salva
- `check_mta_sts_policy_file`: Verifica l'accessibilità e validità del file policy via HTTPS
- `check_tls_rpt_record`: Verifica il record DNS TLS-RPT
- `check_tls_rpt_record!`: Verifica e salva

Il metodo `check_dns` è stato esteso per includere le verifiche MTA-STS e TLS-RPT.

**Verifica HTTPS della Policy:**
Il metodo `check_mta_sts_policy_file` effettua i seguenti controlli:
- Connessione HTTPS a `https://mta-sts.domain.com/.well-known/mta-sts.txt`
- Verifica del certificato SSL
- Verifica che il server risponda con HTTP 200
- Validazione del contenuto del file policy:
  - Presenza di `version: STSv1`
  - Presenza di una modalità valida (testing, enforce, none)
  - Presenza di un valore max_age valido
- Timeout configurato a 10 secondi per apertura e lettura
- Gestione dettagliata degli errori (SSL, timeout, HTTP, formato)

### 4. Controller MTA-STS
**File:** `app/controllers/mta_sts_controller.rb`

Serve la policy MTA-STS tramite l'endpoint pubblico:
- **Route:** `GET /.well-known/mta-sts.txt`
- **Host:** `mta-sts.domain.com`
- Restituisce il file policy in formato plain text
- Cache-Control header configurato con max_age del dominio
- Verifica che il dominio sia verificato e abbia MTA-STS abilitato

### 5. Controller Domains
**File:** `app/controllers/domains_controller.rb`

#### Nuove actions:
- `edit_security`: Mostra il form di configurazione MTA-STS/TLS-RPT
- `update_security`: Aggiorna le impostazioni di sicurezza
- `check_mta_sts_policy`: Verifica manualmente l'accessibilità del file policy MTA-STS via HTTPS (supporta formati JSON e JS)

### 6. Viste

#### `app/views/domains/setup.html.haml`
Estesa con sezioni per mostrare:
- Istruzioni per configurare il record DNS MTA-STS
- Istruzioni per configurare il record DNS TLS-RPT
- Stato delle verifiche DNS
- Link alla configurazione delle policy
- **Pulsante per testare l'accessibilità del file policy MTA-STS via HTTPS**
- Link diretto per visualizzare il file policy nel browser

#### `app/views/domains/edit_security.html.haml`
Form completo per configurare:
- Abilitazione MTA-STS
- Modalità policy (testing/enforce/none)
- Max age della policy
- Pattern MX personalizzati
- Abilitazione TLS-RPT
- Email per report TLS

### 7. Routes
**File:** `config/routes.rb`

Nuove route aggiunte:
```ruby
# Policy endpoint pubblico
get ".well-known/mta-sts.txt" => "mta_sts#policy"

# Configurazione sicurezza domini (sia per org che per server)
get :edit_security, on: :member
patch :update_security, on: :member
post :check_mta_sts_policy, on: :member  # Verifica manuale policy HTTPS
```

## Come Utilizzare

### 1. Configurazione MTA-STS

1. Accedi alla pagina del dominio
2. Clicca su "Configure MTA-STS & TLS-RPT"
3. Abilita MTA-STS
4. Seleziona la modalità:
   - **Testing**: Ricevi report ma non bloccare email
   - **Enforce**: Rifiuta email non inviate via TLS sicuro
   - **None**: Disabilita MTA-STS
5. Imposta il Max Age (consigliato: 604800 = 7 giorni)
6. Opzionalmente, specifica pattern MX personalizzati
7. Salva le impostazioni

### 2. Configurazione DNS MTA-STS

Dopo aver abilitato MTA-STS, configura i seguenti record DNS:

#### Record TXT
```
Nome: _mta-sts.tuodominio.com
Valore: v=STSv1; id=<policy-id>;
```

#### Record A o CNAME
```
Nome: mta-sts.tuodominio.com
Valore: <IP-o-hostname-del-tuo-postal>
```

### 3. Configurazione TLS-RPT

1. Nella stessa pagina di configurazione, abilita TLS-RPT
2. Specifica un'email per ricevere i report (opzionale)
3. Salva le impostazioni

### 4. Configurazione DNS TLS-RPT

```
Nome: _smtp._tls.tuodominio.com
Tipo: TXT
Valore: v=TLSRPTv1; rua=mailto:tls-reports@tuodominio.com
```

### 5. Verifica DNS

1. Torna alla pagina "DNS Setup"
2. Clicca su "Check my records are correct"
3. Verifica che tutti i record siano configurati correttamente

## Formato File Policy MTA-STS

Il file servito su `https://mta-sts.domain.com/.well-known/mta-sts.txt` ha il seguente formato:

```
version: STSv1
mode: enforce
mx: *.mx.example.com
mx: mx1.example.com
max_age: 604800
```

## Note Tecniche

### Policy ID
L'ID della policy viene generato automaticamente tramite hash SHA256 della configurazione corrente (modo, max_age, pattern MX, timestamp). Questo garantisce che l'ID cambi ogni volta che la policy viene modificata, forzando i client a scaricare la nuova policy.

### Cache
Il file policy viene servito con header `Cache-Control` configurato secondo il `max_age` del dominio, permettendo ai server di posta di cachare la policy per il periodo specificato.

### Sicurezza
- Solo i domini verificati possono servire policy MTA-STS
- Il controller MTA-STS è pubblico (no autenticazione richiesta)
- Supporta hosting di più domini sulla stessa istanza Postal

### Pattern MX
Se non specificati pattern MX personalizzati, vengono utilizzati automaticamente gli MX record configurati in `Postal::Config.dns.mx_records` con wildcard (`*.mx.example.com`).

## Riferimenti

- [RFC 8461 - MTA-STS](https://datatracker.ietf.org/doc/html/rfc8461)
- [RFC 8460 - TLS-RPT](https://datatracker.ietf.org/doc/html/rfc8460)

## Testing

Per testare l'implementazione:

1. Configura un dominio di test
2. Abilita MTA-STS in modalità "testing"
3. Configura i record DNS
4. Verifica che il file policy sia accessibile: `curl https://mta-sts.tuodominio.com/.well-known/mta-sts.txt`
5. Usa strumenti online come [MTA-STS Validator](https://aykevl.nl/apps/mta-sts/) per validare la configurazione
6. Dopo alcuni giorni di testing, passa a modalità "enforce"

## Troubleshooting

### Policy non accessibile
- Verifica che il record A/CNAME per mta-sts.domain.com punti correttamente
- Verifica che il certificato SSL sia valido per mta-sts.domain.com
- Controlla i log di Postal per errori

### Record DNS non verificati
- Attendi la propagazione DNS (può richiedere fino a 48 ore)
- Verifica che i record siano configurati correttamente nel tuo provider DNS
- Usa `dig` o `nslookup` per verificare i record manualmente

### Email rifiutate in modalità enforce
- Torna temporaneamente a modalità "testing"
- Verifica i pattern MX specificati
- Controlla i report TLS-RPT per dettagli sugli errori

