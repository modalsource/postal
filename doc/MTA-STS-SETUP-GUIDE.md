# Setup completo MTA-STS per Postal

Questa guida ti aiuta a configurare completamente MTA-STS per i tuoi domini in Postal.

## Cos'è MTA-STS?

MTA-STS (Mail Transfer Agent Strict Transport Security) è uno standard di sicurezza email che:
- Forza l'uso di TLS per le connessioni email
- Previene attacchi man-in-the-middle
- Specifica quali mail server sono autorizzati per il dominio

## Componenti necessari

### 1. Configurazione Rails ✅
Già configurato in Postal:
- Controller MTA-STS per servire le policy
- Modello Domain con supporto MTA-STS
- Route pubbliche per `/.well-known/mta-sts.txt`

### 2. DNS Records
Devi configurare questi record DNS:

```dns
; Record MTA-STS (obbligatorio)
_mta-sts.example.com.  IN  TXT  "v=STSv1; id=<policy-id>"

; A record per il sottodominio mta-sts (obbligatorio)
mta-sts.example.com.   IN  A    123.456.789.0

; Record TLS-RPT (opzionale ma raccomandato)
_smtp._tls.example.com. IN TXT "v=TLSRPTv1; rua=mailto:tls-reports@example.com"
```

### 3. Certificato SSL
Hai bisogno di un certificato SSL valido per `mta-sts.example.com`

**Opzione A: Certificato Wildcard** (raccomandato)
```bash
certbot certonly --dns-cloudflare -d "*.example.com" -d "example.com"
```

**Opzione B: Certificato specifico**
```bash
certbot certonly --nginx -d "mta-sts.example.com"
```

### 4. Reverse Proxy (Nginx)
Configura nginx per servire l'endpoint MTA-STS pubblicamente.

**IMPORTANTE:** L'endpoint `/.well-known/mta-sts.txt` **DEVE** essere pubblico (senza autenticazione).

Vedi: `doc/MTA-STS-NGINX-CONFIG.md` per esempi di configurazione.

## Procedura di setup passo-passo

### Step 1: Abilita MTA-STS per il dominio in Postal

1. Accedi all'interfaccia web di Postal
2. Vai al tuo server → Domains
3. Seleziona il dominio
4. Vai alla sezione "Security Settings"
5. Abilita MTA-STS:
   - **Enable MTA-STS:** Sì
   - **Mode:** `testing` (per iniziare)
   - **Max Age:** `86400` (24 ore)
   - **MX Patterns:** Lascia vuoto per usare i default di Postal

### Step 2: Ottieni i valori DNS

Dopo aver abilitato MTA-STS, Postal ti mostrerà i record DNS da configurare:

```
_mta-sts.example.com.  IN  TXT  "v=STSv1; id=abc123def456"
```

Il `policy-id` (abc123def456) cambia automaticamente quando modifichi la configurazione MTA-STS.

### Step 3: Configura il DNS

Aggiungi i record DNS nel tuo provider:

1. **Record _mta-sts (TXT):**
   - Name: `_mta-sts`
   - Type: `TXT`
   - Value: `v=STSv1; id=<il-tuo-policy-id>`

2. **Record mta-sts (A):**
   - Name: `mta-sts`
   - Type: `A`
   - Value: `<IP-del-tuo-server-postal>`

3. **Record _smtp._tls (TXT) - Opzionale:**
   - Name: `_smtp._tls`
   - Type: `TXT`
   - Value: `v=TLSRPTv1; rua=mailto:tls-reports@example.com`

Attendi la propagazione DNS (può richiedere fino a 24-48 ore).

### Step 4: Configura Nginx

**Se non hai Nginx configurato**, segui `doc/MTA-STS-NGINX-CONFIG.md`

**Se hai già Nginx**, assicurati che:
1. Ci sia un server block per `mta-sts.*`
2. Certificato SSL valido
3. L'endpoint `/.well-known/mta-sts.txt` sia **pubblico** (senza auth_basic)

Configurazione minima:

```nginx
server {
    listen 443 ssl http2;
    server_name mta-sts.*;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location = /.well-known/mta-sts.txt {
        auth_basic off;  # Nessuna autenticazione!
        proxy_pass http://postal:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Ricarica nginx:
```bash
nginx -t && systemctl reload nginx
```

### Step 5: Verifica la configurazione

#### 5.1 Test DNS
```bash
# Verifica record MTA-STS
dig +short TXT _mta-sts.example.com
# Output atteso: "v=STSv1; id=abc123def456"

# Verifica A record
dig +short mta-sts.example.com
# Output atteso: 123.456.789.0
```

#### 5.2 Test HTTPS
```bash
# Test endpoint MTA-STS
curl -v https://mta-sts.example.com/.well-known/mta-sts.txt

# Output atteso:
# HTTP/2 200
# content-type: text/plain; charset=utf-8
#
# version: STSv1
# mode: testing
# mx: *.mx.example.com
# max_age: 86400
```

#### 5.3 Test da Postal UI
1. Vai a Domains → Il tuo dominio → Security Settings
2. Clicca "Check MTA-STS Policy"
3. Dovresti vedere: ✅ "Policy file is accessible and valid"

**Se ricevi errore 403**, vedi `doc/MTA-STS-TROUBLESHOOTING-403.md`

### Step 6: Passa a mode "enforce"

Dopo aver verificato che tutto funzioni in modalità "testing" per almeno 1-2 settimane:

1. Vai su Postal UI → Domains → Security Settings
2. Cambia **Mode** da `testing` a `enforce`
3. Salva
4. Il `policy-id` DNS cambierà automaticamente
5. Aggiorna il record DNS `_mta-sts` con il nuovo ID

## Testing con strumenti esterni

### MTA-STS Validator online
```
https://aykevl.nl/apps/mta-sts/
```

Inserisci il tuo dominio per verificare:
- Record DNS _mta-sts
- Policy file accessibilità
- Certificato SSL
- Validità della policy

### Google Postmaster Tools
Se invii email a Gmail, monitora i report TLS in:
```
https://postmaster.google.com/
```

## Modalità MTA-STS

### Testing (raccomandato per iniziare)
```
mode: testing
```
- I mail server verificano la policy ma **non** bloccano le email se fallisce
- Usato per testare la configurazione
- I report TLS mostrano eventuali problemi
- **Raccomandato per le prime 1-2 settimane**

### Enforce (produzione)
```
mode: enforce
```
- I mail server **devono** rispettare la policy
- Le email vengono rifiutate se la consegna sicura fallisce
- Usa solo dopo aver testato con `testing`

### None (disabilitato)
```
mode: none
```
- Policy pubblicata ma non applicata
- Equivalente a MTA-STS disabilitato

## Max Age

Raccomandazioni:

| Modalità | Max Age | Descrizione |
|----------|---------|-------------|
| Testing  | 86400 (1 giorno) | Per testing iniziale |
| Enforce  | 604800 (7 giorni) | Per produzione stabile |
| Enforce  | 31536000 (1 anno) | Per configurazioni molto stabili |

**Attenzione:** Un max_age alto significa che i mail server cacheranno la policy più a lungo. Se devi fare modifiche, potrebbero volerci giorni/settimane prima che tutti i server aggiornino.

## MX Patterns

### Default (lascia vuoto)
Postal usa automaticamente i suoi MX server configurati in `config/postal.yml`:
```
mx: *.mx.postal.example.com
```

### Custom
Puoi specificare pattern personalizzati (uno per riga):
```
*.mx1.example.com
*.mx2.example.com
mail.example.com
```

## Troubleshooting

### Problema: HTTP 403 quando verifico la policy
**Soluzione:** Vedi `doc/MTA-STS-TROUBLESHOOTING-403.md`

### Problema: DNS non si propaga
```bash
# Forza refresh DNS
dig @8.8.8.8 +short TXT _mta-sts.example.com
```

### Problema: Certificato SSL non valido
```bash
# Verifica certificato
openssl s_client -connect mta-sts.example.com:443 \
  -servername mta-sts.example.com | grep -A 2 "Verify return code"
```

### Problema: La policy non viene servita
```bash
# Test locale (bypassa nginx)
ruby script/test_mta_sts_endpoint.rb example.com
```

## Monitoring

### Log Rails
```bash
tail -f log/production.log | grep -i mta-sts
```

Output normale:
```
MTA-STS policy request - Host: mta-sts.example.com, Extracted domain: example.com
MTA-STS policy served successfully for domain: example.com
```

### TLS-RPT Reports
Se hai configurato TLS-RPT, riceverai email giornaliere con statistiche:
- Numero di connessioni TLS riuscite
- Fallimenti di validazione certificati
- Altri problemi di connessione

## Sicurezza

### Best Practices
1. ✅ Usa sempre certificati SSL validi (Let's Encrypt va bene)
2. ✅ Inizia con mode `testing`, passa a `enforce` dopo test
3. ✅ Monitora i report TLS-RPT per identificare problemi
4. ✅ Usa max_age conservativi (1 settimana) finché non sei sicuro
5. ✅ Non pubblicare mai credenziali nei MX patterns

### Cosa NON fare
1. ❌ Non usare `enforce` senza testare prima con `testing`
2. ❌ Non usare max_age molto alti (>1 anno) se la tua infra cambia spesso
3. ❌ Non dimenticare di aggiornare il DNS quando cambi la policy
4. ❌ Non usare certificati self-signed in produzione
5. ❌ Non proteggere `/.well-known/mta-sts.txt` con autenticazione

## Riferimenti

- [RFC 8461 - MTA-STS](https://tools.ietf.org/html/rfc8461)
- [RFC 8460 - TLS-RPT](https://tools.ietf.org/html/rfc8460)
- [Documentazione implementazione Postal](doc/MTA-STS-IMPLEMENTATION-SUMMARY.md)
- [Configurazione Nginx](doc/MTA-STS-NGINX-CONFIG.md)
- [Troubleshooting 403](doc/MTA-STS-TROUBLESHOOTING-403.md)

