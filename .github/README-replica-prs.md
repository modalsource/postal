# Configurazione Replica PR Upstream

Questo workflow automatizza la replica delle Pull Request dal repository upstream `postalserver/postal` nel fork corrente.

## Configurazione richiesta

### 1. Creare un Personal Access Token (PAT)

Il workflow richiede un Personal Access Token con i seguenti permessi:

1. Vai su GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Genera un nuovo token con i seguenti scope:
   - `repo` (accesso completo ai repository)
   - `workflow` (per modificare i workflow)

### 2. Aggiungere il token come secret

1. Nel tuo repository fork, vai su Settings → Secrets and variables → Actions
2. Clicca "New repository secret"
3. Nome: `REPO_ACCESS_TOKEN`
4. Valore: il token generato al passo precedente

## Come funziona

### Trigger automatico
- Esecuzione ogni 6 ore tramite cron job
- Esecuzione manuale tramite workflow dispatch

### Processo di replica
1. **Scansione PR**: Cerca tutte le PR aperte nel repository upstream
2. **Controllo duplicati**: Verifica se una PR è già stata replicata
3. **Clone repository**: Clona il branch della PR dal repository originale
4. **Push al fork**: Invia il branch al tuo fork
5. **Creazione PR**: Crea una nuova PR nel fork con prefisso "Replica:"

### Gestione degli errori
- Fallback per problemi di clone (shallow → full clone)
- Gestione timeout per operazioni lunghe
- Skip automatico di PR già replicate o branch esistenti
- Logging dettagliato per debugging

## Personalizzazione

### Modificare la frequenza
Modifica la sezione `cron` nel file `.github/workflows/replica-pr.yml`:
```yaml
schedule:
  - cron: '0 */12 * * *'  # Ogni 12 ore invece di 6
```

### Modificare il repository upstream
Modifica la variabile `UPSTREAM_REPO` nel workflow:
```yaml
env:
  UPSTREAM_REPO: altro-utente/altro-repo
```

## Risoluzione problemi

### Errore "Resource not accessible by integration"
- Verifica che il token `REPO_ACCESS_TOKEN` sia configurato correttamente
- Assicurati che il token abbia i permessi `repo` completi

### Errore "Errore nel clone del repository"
- Controlla che il repository upstream sia pubblico o che tu abbia accesso
- Verifica la connessione di rete del runner GitHub

### PR non vengono create
- Controlla i log del workflow per errori specifici
- Verifica che il token abbia permessi di scrittura sul repository fork

## Monitoraggio

I log del workflow mostrano:
- ✅ PR replicate con successo
- ⏭️ PR saltate (già esistenti)
- ❌ Errori con dettagli specifici
- 📊 Riepilogo finale con statistiche
