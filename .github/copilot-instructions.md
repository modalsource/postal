# Copilot Instructions

## Contesto del progetto

Questo è un progetto Ruby on Rails per un servizio di mail/email con funzionalità avanzate di routing, tracking e webhook.

## Linee guida generali

- Segui le best practice di Ruby on Rails 7.0
- Utilizza ActiveRecord per l'accesso al database
- **NON modificare mai direttamente il file `db/schema.rb`** - usa sempre le migration
- Scrivi test automatici per ogni nuova funzionalità
- Mantieni il codice pulito e ben documentato
- Rispetta le convenzioni di naming Rails per modelli, controller e viste
- Assicurati che tutte le query siano sicure da SQL injection

## Struttura del database

- **Charset**: `utf8mb4` con collation `utf8mb4_general_ci` per tutte le tabelle
- **Primary Keys**: Utilizza `:integer` come tipo per gli ID
- **UUIDs**: Molte entità utilizzano campi `uuid` per identificatori esterni
- **Timestamps**: Usa `precision: nil` per mantenere compatibilità

## Entità principali

- **Organizations**: Organizzazioni con utenti e server
- **Servers**: Server di posta con modalità e limiti di invio
- **Domains**: Domini verificati con controlli DNS/DKIM/SPF
- **Routes**: Routing dei messaggi verso endpoint
- **Endpoints**: HTTP, SMTP e Address endpoints per delivery
- **Messages**: Sistema di code per messaggi (`queued_messages`)
- **Webhooks**: Sistema di notifiche con retry automatico
- **Users**: Autenticazione con Authie sessions

## Best practices specifiche

- Usa sempre indici sui campi `uuid` con lunghezza limitata (es. `length: 8`)
- Per i campi di stato usa enum o stringhe con validazioni
- Implementa soft delete con campi `deleted_at` dove appropriato
- Gestisci retry e locking per sistemi asincroni (`locked_by`, `locked_at`)
- Usa `decimal` per soglie e percentuali con precisione definita
- Includi sempre timestamp per audit trail
- Per servizi esterni (SpamAssassin, ClamAV, Truemail) usa timeout e gestione errori robusta

## Sicurezza

- Non includere mai credenziali in chiaro nel codice
- Usa token hash per autenticazione (`token_hash` vs `token`)
- Implementa rate limiting e soglie spam
- Valida sempre input da webhook e API esterne

## Performance

- Usa indici appropriati per query frequenti
- Implementa paginazione per liste lunghe
- Considera il caching per dati di configurazione
- Monitora query N+1 con includes/joins

## Integrazione Truemail

Prompt: aggiungi la fase di sviluppo per integrare le funzionalità di truemail. L'integrazione deve avvennire come avviene per spamassassin (spamd) e clamav, quindi devi aggiungere la configurazione per abilitarlo e configurarlo. La modalità di integrazione di truemail è tramite API che verranno esposte da truemail-rack deploiato in un container docker a parte, la documentazione dell'endpoint è qui: https://truemail-rb.org/truemail-rack/#/endpoints . Inoltre, in ogni singolo mail server si potrà configurare se abilitare o meno la verifica dell'indirizzo prima dell'invio mail

## Fase di sviluppo per l'integrazione di Truemail
- Configurazione globale: Aggiungere le impostazioni Truemail al sistema di configurazione principale
- Configurazione per server: Estendere il modello Server per permettere l'abilitazione per singolo server
- Client API: Creare un client per comunicare con l'API Truemail
- Integrazione nella pipeline: Aggiungere la validazione prima dell'invio mail
- Interface web: Aggiungere controlli nell'interfaccia di amministrazione
