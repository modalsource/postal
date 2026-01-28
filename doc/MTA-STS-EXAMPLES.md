# Esempi Pratici - Verifica HTTPS MTA-STS Policy

## Scenario 1: Configurazione e Test di un Nuovo Dominio

### Passo 1: Aggiungi il dominio
```
1. Vai su Postal → Organization → Server → Domains
2. Clicca "Add Domain"
3. Inserisci "example.com"
4. Verifica il dominio (DNS o Email)
```

### Passo 2: Abilita MTA-STS
```
1. Vai alla pagina del dominio
2. Clicca "Configure MTA-STS & TLS-RPT"
3. Spunta "Enable MTA-STS"
4. Seleziona modalità "Testing"
5. Imposta Max Age: 86400 (1 giorno per test)
6. Lascia vuoti i pattern MX (usa default)
7. Clicca "Save Security Settings"
```

### Passo 3: Configura DNS
```
1. Nel tuo provider DNS, aggiungi:

   Record TXT:
   Nome: _mta-sts.example.com
   Valore: v=STSv1; id=20251107abc123;
   
   Record A o CNAME:
   Nome: mta-sts.example.com
   Valore: postal.yourserver.com (o IP del tuo Postal)
```

### Passo 4: Verifica Policy File
```
1. Torna alla pagina "DNS Setup" del dominio
2. Nella sezione MTA-STS, clicca "Test MTA-STS Policy File"
3. Dovresti vedere: "MTA-STS policy file is accessible and valid"
```

### Passo 5: Verifica Completa DNS
```
1. Clicca "Check my records are correct"
2. Postal verificherà:
   - SPF Record ✓
   - DKIM Record ✓
   - MX Records ✓
   - Return Path ✓
   - MTA-STS DNS Record ✓
   - MTA-STS HTTPS Policy ✓ (NUOVO!)
```

## Scenario 2: Debugging Errore SSL

### Problema
```
SSL certificate error for https://mta-sts.example.com/.well-known/mta-sts.txt: 
certificate verify failed (unable to get local issuer certificate)
```

### Soluzione
```
1. Verifica che il certificato SSL copra il sottodominio:
   - Certificato per *.example.com (wildcard), oppure
   - Certificato per mta-sts.example.com (specifico)

2. Se usi Let's Encrypt, rigenera il certificato includendo SAN:
   certbot certonly --webroot -w /var/www/html \
     -d example.com \
     -d mta-sts.example.com \
     -d www.example.com

3. Ricarica il server web (nginx/apache)

4. Riprova il test in Postal
```

### Verifica Manuale del Certificato
```bash
# Controlla il certificato SSL
openssl s_client -connect mta-sts.example.com:443 -servername mta-sts.example.com < /dev/null 2>/dev/null | openssl x509 -noout -text | grep DNS

# Dovrebbe mostrare:
# DNS:example.com, DNS:mta-sts.example.com, DNS:*.example.com
```

## Scenario 3: Debugging HTTP 404

### Problema
```
Policy file returned HTTP 404. Expected 200. 
URL: https://mta-sts.example.com/.well-known/mta-sts.txt
```

### Diagnosi
```bash
# Test manuale con curl
curl -v https://mta-sts.example.com/.well-known/mta-sts.txt

# Controlla la risposta HTTP
```

### Possibili Cause

#### Causa 1: DNS non punta a Postal
```
1. Verifica il record DNS:
   dig mta-sts.example.com
   
2. Dovrebbe puntare al tuo server Postal
```

#### Causa 2: MTA-STS non abilitato in Postal
```
1. Vai in "Configure MTA-STS & TLS-RPT"
2. Assicurati che "Enable MTA-STS" sia spuntato
3. Salva le impostazioni
```

#### Causa 3: Server web non configurato
```
1. Se usi un reverse proxy (nginx/apache), assicurati che:
   - Il dominio mta-sts.example.com sia configurato
   - Le richieste .well-known vengano passate a Postal
   
Esempio nginx:
server {
    server_name mta-sts.example.com;
    
    location /.well-known/mta-sts.txt {
        proxy_pass http://postal_backend;
        proxy_set_header Host $host;
    }
}
```

## Scenario 4: Policy con Pattern MX Personalizzati

### Configurazione
```
1. Vai in "Configure MTA-STS & TLS-RPT"
2. In "MX Patterns", inserisci (uno per riga):
   mx1.example.com
   mx2.example.com
   backup-mx.example.com
3. Salva
```

### Verifica del Contenuto
```bash
# Controlla il contenuto della policy
curl https://mta-sts.example.com/.well-known/mta-sts.txt

# Output atteso:
version: STSv1
mode: testing
mx: mx1.example.com
mx: mx2.example.com
mx: backup-mx.example.com
max_age: 86400
```

## Scenario 5: Passaggio da Testing a Enforce

### Raccomandazioni
```
1. Usa modalità "testing" per almeno 7 giorni
2. Monitora i report TLS-RPT per errori
3. Aumenta gradualmente il max_age:
   - Giorno 1-7: 86400 (1 giorno)
   - Giorno 8-14: 604800 (7 giorni)
   - Giorno 15+: 2592000 (30 giorni) in modalità enforce
```

### Procedura
```
1. Vai in "Configure MTA-STS & TLS-RPT"
2. Cambia modalità da "testing" a "enforce"
3. Aumenta max_age a 604800
4. Salva
5. Il DNS record _mta-sts si aggiornerà automaticamente con nuovo ID
6. Clicca "Test MTA-STS Policy File" per conferma
```

## Scenario 6: API Testing

### Test Manuale via cURL
```bash
# Login e ottieni cookie di sessione
curl -c cookies.txt -X POST https://postal.example.com/login \
  -d "email_address=admin@example.com" \
  -d "password=yourpassword"

# Test policy file
curl -b cookies.txt -X POST \
  https://postal.example.com/org/myorg/servers/myserver/domains/DOMAIN-UUID/check_mta_sts_policy \
  -H "Accept: application/json"

# Output atteso (successo):
{
  "success": true,
  "message": "MTA-STS policy file is accessible and valid at https://mta-sts.example.com/.well-known/mta-sts.txt",
  "url": "https://mta-sts.example.com/.well-known/mta-sts.txt"
}

# Output atteso (errore):
{
  "success": false,
  "error": "Policy file returned HTTP 404. Expected 200. URL: https://mta-sts.example.com/.well-known/mta-sts.txt",
  "url": "https://mta-sts.example.com/.well-known/mta-sts.txt"
}
```

## Scenario 7: Monitoraggio e Logging

### Log delle Richieste
```bash
# Tail dei log di Postal
tail -f log/development.log | grep -i mta-sts

# Esempio di log per richiesta di verifica:
Started POST "/org/myorg/servers/myserver/domains/abc123/check_mta_sts_policy"
Processing by DomainsController#check_mta_sts_policy
Completed 200 OK
```

### Verifica da Riga di Comando Rails
```bash
# Entra nella console Rails
bundle exec rails console

# Trova il dominio
domain = Domain.find_by(name: 'example.com')

# Verifica manualmente
result = domain.check_mta_sts_policy_file
puts result.inspect

# Output:
# {:success=>true} oppure
# {:success=>false, :error=>"..."}

# Verifica completa DNS (include HTTPS)
domain.check_mta_sts_record
puts domain.mta_sts_status  # "OK", "Invalid", "Missing"
puts domain.mta_sts_error    # nil oppure messaggio errore
```

## Scenario 8: Troubleshooting Timeout

### Problema
```
Timeout while fetching policy file from https://mta-sts.example.com/.well-known/mta-sts.txt: 
execution expired
```

### Diagnosi
```bash
# Test connessione manuale
time curl -v https://mta-sts.example.com/.well-known/mta-sts.txt

# Se impiega più di 10 secondi:
# 1. Controlla firewall
# 2. Controlla performance del server
# 3. Controlla latenza di rete
```

### Soluzione Temporanea (solo sviluppo!)
```ruby
# In app/models/concerns/has_dns_checks.rb
# Aumenta i timeout (NON raccomandato in produzione):
http.open_timeout = 30  # invece di 10
http.read_timeout = 30  # invece di 10
```

## Riferimenti Utili

### Validatori Online
- https://aykevl.nl/apps/mta-sts/ - Validator MTA-STS completo
- https://mxtoolbox.com/SuperTool.aspx - Tool DNS generico

### Comandi Utili
```bash
# Verifica record DNS TXT
dig TXT _mta-sts.example.com

# Verifica record A/CNAME
dig mta-sts.example.com

# Test HTTPS con dettagli SSL
curl -vvv https://mta-sts.example.com/.well-known/mta-sts.txt

# Test da console Rails
bundle exec rails console
Domain.find_by(name: 'example.com').check_mta_sts_policy_file
```

