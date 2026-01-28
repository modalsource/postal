# Implementazione Verifica HTTPS Policy MTA-STS

## Panoramica
È stata aggiunta la funzionalità di verifica HTTPS del file policy MTA-STS in Postal. Questa funzionalità verifica che il file policy sia accessibile e valido tramite HTTPS all'URL `https://mta-sts.domain.com/.well-known/mta-sts.txt`.

## File Modificati

### 1. `app/models/concerns/has_dns_checks.rb`
**Modifiche:**
- Metodo `check_mta_sts_record` esteso per includere la verifica HTTPS
- Aggiunto metodo `check_mta_sts_policy_file` per verificare l'accessibilità e validità del file policy

**Funzionalità:**
- Connessione HTTPS con verifica certificato SSL
- Timeout di 10 secondi per apertura e lettura
- Validazione del contenuto:
  - Verifica presenza `version: STSv1`
  - Verifica modalità valida (testing/enforce/none)
  - Verifica valore max_age
- Gestione errori dettagliata:
  - Errori SSL (certificato non valido)
  - Timeout di connessione
  - Errori HTTP (404, 500, ecc.)
  - Contenuto non valido

### 2. `app/models/domain.rb`
**Aggiunto:**
- Metodo `mta_sts_policy_url`: ritorna l'URL completo della policy

### 3. `app/controllers/domains_controller.rb`
**Aggiunto:**
- Action `check_mta_sts_policy`: permette di verificare manualmente il file policy
- Supporta risposte in formato JSON e JavaScript

### 4. `app/views/domains/setup.html.haml`
**Modifiche:**
- Aggiunto pulsante "Test MTA-STS Policy File" per verificare manualmente
- Aggiunto link "View Policy File" per aprire il file in una nuova tab
- Messaggio di stato aggiornato per indicare verifica DNS + HTTPS

### 5. `app/views/domains/check_mta_sts_policy.js.erb`
**Nuovo file:**
- Gestisce la risposta AJAX del test manuale
- Mostra notifiche di successo/errore all'utente

### 6. `config/routes.rb`
**Aggiunto:**
- Route `post :check_mta_sts_policy, on: :member` per entrambi i contesti (organization e server)

### 7. `doc/MTA-STS-AND-TLS-RPT.md`
**Aggiornato:**
- Documentazione completa della funzionalità di verifica HTTPS
- Esempi di utilizzo e troubleshooting

### 8. `spec/models/mta_sts_spec.rb`
**Nuovo file:**
- Test RSpec per la verifica del file policy
- Copertura di vari scenari (successo, errori HTTP, SSL, timeout, ecc.)

## Come Funziona

### Verifica Automatica (durante check DNS)
Quando un utente clicca su "Check my records are correct", il sistema:
1. Verifica il record DNS TXT `_mta-sts.domain.com`
2. **NUOVO:** Effettua una richiesta HTTPS a `https://mta-sts.domain.com/.well-known/mta-sts.txt`
3. Valida il certificato SSL
4. Verifica che il server risponda con HTTP 200
5. Valida il contenuto del file policy
6. Aggiorna lo stato in `mta_sts_status` e `mta_sts_error`

### Verifica Manuale
Nella pagina "DNS Setup", quando MTA-STS è abilitato, l'utente può:
1. Cliccare su "Test MTA-STS Policy File" per verificare solo il file policy
2. Cliccare su "View Policy File" per aprire il file nel browser
3. Ricevere feedback immediato su eventuali problemi

## Esempio di Utilizzo

### Via Web UI
1. Vai alla pagina del dominio
2. Clicca su "DNS Setup"
3. Se MTA-STS è abilitato, vedrai la sezione MTA-STS
4. Clicca su "Test MTA-STS Policy File" per verificare
5. Riceverai una notifica verde se tutto è OK, oppure rossa con i dettagli dell'errore

### Via API
```bash
# Test manuale del file policy
curl -X POST \
  https://postal.example.com/org/myorg/servers/myserver/domains/UUID/check_mta_sts_policy \
  -H 'Content-Type: application/json' \
  -H 'Cookie: session=...'
```

Risposta in caso di successo:
```json
{
  "success": true,
  "message": "MTA-STS policy file is accessible and valid at https://mta-sts.example.com/.well-known/mta-sts.txt",
  "url": "https://mta-sts.example.com/.well-known/mta-sts.txt"
}
```

Risposta in caso di errore:
```json
{
  "success": false,
  "error": "SSL certificate error for https://mta-sts.example.com/.well-known/mta-sts.txt: certificate verify failed",
  "url": "https://mta-sts.example.com/.well-known/mta-sts.txt"
}
```

## Messaggi di Errore

### Errori SSL
```
SSL certificate error for https://mta-sts.example.com/.well-known/mta-sts.txt: certificate verify failed
```
**Causa:** Il certificato SSL non è valido o non copre il sottodominio mta-sts
**Soluzione:** Assicurati che il certificato SSL copra `*.domain.com` o `mta-sts.domain.com`

### Errori HTTP
```
Policy file returned HTTP 404. Expected 200. URL: https://mta-sts.example.com/.well-known/mta-sts.txt
```
**Causa:** Il file policy non è accessibile all'URL specificato
**Soluzione:** Verifica che il record A/CNAME per mta-sts.domain.com punti correttamente e che Postal stia servendo il file

### Errori di Timeout
```
Timeout while fetching policy file from https://mta-sts.example.com/.well-known/mta-sts.txt: execution expired
```
**Causa:** Il server non risponde entro 10 secondi
**Soluzione:** Verifica che il server sia raggiungibile e non ci siano problemi di firewall

### Errori di Contenuto
```
Policy file doesn't contain 'version: STSv1'. URL: https://mta-sts.example.com/.well-known/mta-sts.txt
```
**Causa:** Il contenuto del file policy non è valido
**Soluzione:** Verifica che MTA-STS sia abilitato correttamente in Postal e che la configurazione sia salvata

## Testing

Per testare la funzionalità:

```bash
# Esegui i test RSpec
bundle exec rspec spec/models/mta_sts_spec.rb
```

## Note Tecniche

- **Timeout:** 10 secondi per apertura + 10 secondi per lettura
- **Verifica SSL:** OpenSSL::SSL::VERIFY_PEER (certificato deve essere valido)
- **Caching:** La verifica NON è cachata, viene eseguita ad ogni richiesta
- **Performance:** La verifica HTTPS viene eseguita solo quando check_dns viene chiamato o quando viene richiesta manualmente

## Compatibilità

- Rails 7.0+
- Ruby 2.7+
- Richiede gem `net/http` (inclusa in Ruby standard library)

## Troubleshooting

### Il test manuale funziona ma check DNS fallisce
Il metodo `check_dns` esegue più controlli in sequenza. Verifica gli altri record DNS (SPF, DKIM, MX) per assicurarti che non ci siano altri problemi.

### Certificato SSL autofirmato in sviluppo
Durante lo sviluppo, se usi certificati autofirmati, potresti voler temporaneamente disabilitare la verifica SSL modificando `http.verify_mode` in `has_dns_checks.rb`. **NON farlo in produzione!**

### Rete locale / Docker
Se Postal è in esecuzione in Docker o in una rete locale, assicurati che possa raggiungere il dominio pubblico per la verifica HTTPS.

