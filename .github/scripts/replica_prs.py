import os
import sys
import subprocess
import tempfile
from github import Github
from github.GithubException import GithubException
import time

def run_git_command(command, cwd=None, timeout=300):
    """Esegue un comando git e gestisce gli errori"""
    try:
        # Masking del token per il logging
        safe_command = command.replace(os.environ.get("GH_TOKEN", ""), "***") if "GH_TOKEN" in os.environ else command
        print(f"    🔧 Eseguendo: {safe_command}")
        print(f"    📁 Directory: {cwd or 'corrente'}")

        # Aggiungi diagnostica ambiente prima del comando git
        if "git clone" in command:
            print(f"    🔍 Diagnostica ambiente:")
            try:
                # Verifica versione git
                git_version = subprocess.run("git --version", shell=True, capture_output=True, text=True, timeout=10)
                print(f"      - Git version: {git_version.stdout.strip() if git_version.returncode == 0 else 'N/A'}")

                # Verifica configurazione git
                git_user = subprocess.run("git config --global user.name", shell=True, capture_output=True, text=True, timeout=10)
                git_email = subprocess.run("git config --global user.email", shell=True, capture_output=True, text=True, timeout=10)
                print(f"      - Git user: {git_user.stdout.strip() if git_user.returncode == 0 else 'Non configurato'}")
                print(f"      - Git email: {git_email.stdout.strip() if git_email.returncode == 0 else 'Non configurato'}")

                # Verifica connettività GitHub
                connectivity = subprocess.run("curl -s -o /dev/null -w '%{http_code}' https://github.com", shell=True, capture_output=True, text=True, timeout=15)
                print(f"      - GitHub connectivity: {connectivity.stdout.strip() if connectivity.returncode == 0 else 'Errore'}")

                # Verifica spazio disco disponibile
                if cwd and os.path.exists(os.path.dirname(cwd)):
                    disk_usage = subprocess.run(f"df -h {os.path.dirname(cwd)}", shell=True, capture_output=True, text=True, timeout=5)
                    if disk_usage.returncode == 0:
                        print(f"      - Spazio disco: {disk_usage.stdout.strip().split()[1] if len(disk_usage.stdout.strip().split()) > 10 else 'N/A'}")

            except Exception as diag_e:
                print(f"      - Errore diagnostica: {diag_e}")

        start_time = time.time()
        result = subprocess.run(
            command,
            shell=True,
            cwd=cwd,
            capture_output=True,
            text=True,
            check=True,
            timeout=timeout,
            env=dict(os.environ, GIT_TERMINAL_PROMPT="0")  # Disabilita prompt interattivi
        )
        execution_time = time.time() - start_time

        print(f"    ⏱️  Tempo esecuzione: {execution_time:.2f}s")
        print(f"    ✅ Return code: {result.returncode}")

        # Git spesso invia messaggi di progresso su stderr anche quando ha successo
        has_stdout = result.stdout and result.stdout.strip()
        has_stderr = result.stderr and result.stderr.strip()

        if has_stdout:
            print(f"    📤 STDOUT completo:")
            for line in result.stdout.strip().split('\n'):
                print(f"       {line}")

        if has_stderr:
            # Per git clone e altri comandi, stderr spesso contiene messaggi di progresso normali
            if "git clone" in command or "git fetch" in command or "git push" in command:
                print(f"    📋 Messaggi di progresso (stderr):")
            else:
                print(f"    📝 STDERR:")
            for line in result.stderr.strip().split('\n'):
                print(f"       {line}")

        if not has_stdout and not has_stderr:
            print(f"    📤 Nessun output generato")

        # Restituisce True per successo
        return True

    except subprocess.CalledProcessError as e:
        execution_time = time.time() - start_time if 'start_time' in locals() else 0
        safe_command = command.replace(os.environ.get("GH_TOKEN", ""), "***") if "GH_TOKEN" in os.environ else command

        print(f"    ❌ COMANDO FALLITO: {safe_command}")
        print(f"    📁 Directory: {cwd or 'corrente'}")
        print(f"    ⏱️  Tempo esecuzione: {execution_time:.2f}s")
        print(f"    🔢 Return code: {e.returncode}")

        if e.stdout:
            print(f"    📤 STDOUT completo:")
            for line in e.stdout.strip().split('\n'):
                print(f"       {line}")
        else:
            print(f"    📤 STDOUT: (vuoto)")

        if e.stderr:
            print(f"    📝 STDERR completo:")
            for line in e.stderr.strip().split('\n'):
                print(f"       {line}")
        else:
            print(f"    📝 STDERR: (vuoto)")

        # Analisi specifica degli errori comuni
        if e.stderr:
            error_lower = e.stderr.lower()
            if "fatal: could not read" in error_lower:
                print(f"    💡 Suggerimento: Problema di autenticazione o repository non accessibile")
            elif "timeout" in error_lower or "timed out" in error_lower:
                print(f"    💡 Suggerimento: Timeout di rete, prova con timeout maggiore")
            elif "permission denied" in error_lower:
                print(f"    💡 Suggerimento: Problema di permessi sul token o repository")
            elif "repository not found" in error_lower:
                print(f"    💡 Suggerimento: Repository non trovato o non accessibile")
            elif "authentication failed" in error_lower:
                print(f"    💡 Suggerimento: Token non valido o scaduto")
            elif "network is unreachable" in error_lower:
                print(f"    💡 Suggerimento: Problema di connettività di rete")
            elif "name resolution" in error_lower:
                print(f"    💡 Suggerimento: Problema di risoluzione DNS")

        return False

    except subprocess.TimeoutExpired as e:
        safe_command = command.replace(os.environ.get("GH_TOKEN", ""), "***") if "GH_TOKEN" in os.environ else command
        print(f"    ⏰ TIMEOUT: {safe_command}")
        print(f"    📁 Directory: {cwd or 'corrente'}")
        print(f"    ⏱️  Timeout dopo: {timeout}s")

        if hasattr(e, 'stdout') and e.stdout:
            print(f"    📤 STDOUT parziale:")
            for line in e.stdout.strip().split('\n'):
                print(f"       {line}")

        if hasattr(e, 'stderr') and e.stderr:
            print(f"    📝 STDERR parziale:")
            for line in e.stderr.strip().split('\n'):
                print(f"       {line}")

        print(f"    💡 Suggerimento: Comando troppo lento, considera di aumentare il timeout o verificare la connessione")
        return False

def get_git_output(command, cwd=None, timeout=300):
    """Esegue un comando git e restituisce l'output se ha successo"""
    try:
        result = subprocess.run(
            command,
            shell=True,
            cwd=cwd,
            capture_output=True,
            text=True,
            check=True,
            timeout=timeout,
            env=dict(os.environ, GIT_TERMINAL_PROMPT="0")
        )
        return result.stdout.strip()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return None

def setup_git_config(repo_dir):
    """Configura git per evitare errori di configurazione"""
    commands = [
        "git config user.email 'action@github.com'",
        "git config user.name 'GitHub Action'",
        "git config --global credential.helper store",
        "git config --global http.sslverify true"
    ]

    for cmd in commands:
        run_git_command(cmd, cwd=repo_dir)

def setup_git_config_global():
    """Configura git globalmente per evitare errori di configurazione"""
    commands = [
        "git config --global user.email 'action@github.com'",
        "git config --global user.name 'GitHub Action'",
        "git config --global credential.helper store",
        "git config --global http.sslverify true",
        "git config --global init.defaultBranch main"
    ]

    for cmd in commands:
        run_git_command(cmd)

def get_clone_url(pr, gh_token):
    """Genera l'URL di clone appropriato basato sul tipo di repository"""
    repo = pr.head.repo

    # Il repo head può mancare se il fork dell'autore è stato cancellato
    if repo is None:
        return None

    # Se il repository è lo stesso dell'upstream, usa l'URL pubblico
    if repo.full_name == pr.base.repo.full_name:
        return repo.clone_url

    # Per repository privati o fork, usa l'autenticazione
    if repo.private or repo.fork:
        return f"https://{gh_token}@github.com/{repo.full_name}.git"

    return repo.clone_url

def check_branch_exists_in_fork(fork, branch_name):
    """Verifica se un branch esiste già nel fork"""
    try:
        fork.get_branch(branch_name)
        return True
    except GithubException:
        return False

def get_pr_commit_shas(pr):
    """Ottiene gli SHA dei commit della PR originale"""
    try:
        return [commit.sha for commit in pr.commits]
    except Exception as e:
        print(f"  ⚠️  Impossibile ottenere i commit della PR: {e}")
        return None


def get_fork_substitutions():
    """Sostituzioni statiche da applicare ai file replicati per mantenere
    validi nel fork i riferimenti all'infrastruttura upstream
    (es. il nome immagine ghcr: ghcr.io/<upstream> -> ghcr.io/<fork>)."""
    upstream = (os.environ.get("UPSTREAM_REPO") or "").strip().lower()
    fork = (os.environ.get("FORK_REPO") or "").strip().lower()
    if not upstream or not fork or upstream == fork:
        return []
    return [
        # Le workflow CI pubblicano l'immagine container su ghcr.io/<owner>/<repo>:
        # puntarle all'immagine del fork per non rompere la CI replicata.
        (f"ghcr.io/{upstream}", f"ghcr.io/{fork}"),
    ]

def apply_fork_substitutions(repo_dir, pr, base_sha):
    """Applica sostituzioni statiche ai SOLO file modificati dalla replica.

    Le sostituzioni vengono applicate in un commit separato dopo i cherry-pick
    (i commit originali restano intatti). Mai fatale."""
    substitutions = get_fork_substitutions()
    if not substitutions or not base_sha:
        return 0

    diff_output = get_git_output(f"git diff --name-only '{base_sha}' HEAD", cwd=repo_dir)
    if not diff_output:
        return 0

    modified = 0
    for path in [line.strip() for line in diff_output.splitlines() if line.strip()]:
        file_path = os.path.join(repo_dir, path)
        if not os.path.isfile(file_path):
            continue
        try:
            with open(file_path, "r", encoding="utf-8") as handle:
                content = handle.read()
        except (UnicodeDecodeError, OSError):
            print(f"    ⏭️  Sostituzioni saltate (file binario/non testuale): {path}")
            continue
        new_content = content
        for old, new in substitutions:
            new_content = new_content.replace(old, new)
        if new_content != content:
            try:
                with open(file_path, "w", encoding="utf-8") as handle:
                    handle.write(new_content)
            except OSError as e:
                print(f"    ⚠️  Impossibile scrivere {path}: {e}")
                continue
            run_git_command(f"git add '{path}'", cwd=repo_dir)
            modified += 1

    if modified > 0:
        pairs = ", ".join(f"{old} → {new}" for old, new in substitutions)
        print(f"  🔧 Sostituzioni applicate a {modified} file: {pairs}")
        commit_command = f"git commit -m 'Replica: fork-specific substitutions' -m '(Keeps upstream infrastructure references working after replication of {pr.html_url})'"
        if not run_git_command(commit_command, cwd=repo_dir):
            print(f"  ⚠️  Impossibile creare il commit di sostituzioni (non fatale)")
    return modified


def prepare_replica_branch(clone_url, repo_dir, branch_name, fork_url, default_branch, gh_token, pr, fork_branch_name):
    """Prepara il branch di replica clonando il fork e applicando SOLO i commit della PR originale.

    Returns (success, upstream_only_count): upstream_only_count è il numero di commit
    presenti nel main upstream ma non nel fork (solo per tracking, NON vengono replicati).
    """

    # Configura git prima di tutto
    print(f"  🔧 Configurazione preliminare git...")
    setup_git_config_global()

    # Clona il fork: il branch di replica nasce dal main del fork,
    # NON dal main upstream (scope diverso)
    print(f"  📥 Clonando il fork (base: {default_branch})...")
    clone_command = f"git clone --branch {default_branch} '{fork_url}' '{repo_dir}'"
    if not run_git_command(clone_command, timeout=300):
        print(f"  ❌ Impossibile clonare il fork")
        return False, None, 0

    setup_git_config(repo_dir)

    # Scarica i commit della PR originale
    print(f"  📥 Fetch dei commit della PR originale...")
    fetched = run_git_command(f"git fetch '{clone_url}' '{branch_name}'", cwd=repo_dir, timeout=180)
    if not fetched:
        print(f"  🔄 Fallback: fetch da refs/pull/{pr.number}/head...")
        upstream_pr_url = f"https://{gh_token}@github.com/{pr.base.repo.full_name}.git"
        fetched = run_git_command(f"git fetch '{upstream_pr_url}' 'refs/pull/{pr.number}/head'", cwd=repo_dir, timeout=180)
    if not fetched:
        print(f"  ❌ Impossibile scaricare i commit della PR")
        return False, None, 0

    # Crea il branch di replica
    print(f"  🌳 Creando branch di replica {fork_branch_name}...")
    if not run_git_command(f"git checkout -b {fork_branch_name}", cwd=repo_dir):
        print(f"  ❌ Impossibile creare il branch di replica")
        return False, None, 0

    # Snapshot della base del fork (riferimento per le sostituzioni successive)
    base_sha = get_git_output("git rev-parse HEAD", cwd=repo_dir)

    # Applica SOLO i commit della PR originale (mantiene gli autori originali)
    commit_shas = get_pr_commit_shas(pr)
    if commit_shas:
        print(f"  🍒 Applicando {len(commit_shas)} commit della PR originale...")
        for sha in commit_shas:
            if not run_git_command(f"git cherry-pick -x {sha}", cwd=repo_dir, timeout=120):
                print(f"  🔄 Cherry-pick fallito per {sha}, fallback con patch completa della PR...")
                run_git_command("git cherry-pick --abort", cwd=repo_dir)
                patch_url = f"https://github.com/{pr.base.repo.full_name}/pull/{pr.number}.diff"
                if not run_git_command(f"curl -sL '{patch_url}' | git apply --index -", cwd=repo_dir, timeout=180):
                    print(f"  ❌ Impossibile applicare i commit della PR")
                    return False, None, 0
                if not run_git_command(f"git commit -m 'Replica: {pr.title}' -m '(Replicated from {pr.html_url})'", cwd=repo_dir):
                    print(f"  ❌ Impossibile creare il commit di replica")
                    return False, None, 0
                break
    else:
        print(f"  ❌ Nessun commit disponibile per la replica")
        return False, None, 0

    # Sostituzioni statiche (es. nome immagine ghcr upstream -> fork) sui SOLO
    # file modificati dalla replica, per non rompere la CI del fork
    substituted_count = apply_fork_substitutions(repo_dir, pr, base_sha)

    # Tracking della divergenza upstream (best-effort, mai fatale):
    # conta i commit del main upstream non presenti nel fork — solo per tracciamento,
    # NON vengono replicati (scope diverso)
    upstream_only_count = None
    try:
        upstream_base_url = f"https://github.com/{pr.base.repo.full_name}.git"
        if run_git_command(f"git fetch '{upstream_base_url}' '{pr.base.ref}'", cwd=repo_dir, timeout=180):
            count = get_git_output("git rev-list --count HEAD..FETCH_HEAD", cwd=repo_dir)
            if count and count.strip().isdigit():
                upstream_only_count = int(count.strip())
                print(f"  📊 Upstream main è {upstream_only_count} commit avanti (solo tracking, NON replicati)")
    except Exception as e:
        print(f"  ⚠️  Impossibile calcolare la divergenza upstream (non fatale): {e}")

    # Push del branch di replica al fork
    print(f"  📤 Push del branch {fork_branch_name} al fork...")
    if not run_git_command(f"git push origin {fork_branch_name}", cwd=repo_dir, timeout=180):
        print(f"  🔄 Tentativo con force push...")
        if not run_git_command(f"git push --force origin {fork_branch_name}", cwd=repo_dir, timeout=180):
            print(f"  ❌ Push al fork fallito")
            return False, None, 0

    print(f"  ✅ Branch di replica preparato e push completato (solo commit della PR originale)")
    return True, upstream_only_count, substituted_count

def should_skip_pr(pr_title):
    """Determina se una PR deve essere saltata basandosi sul titolo"""
    skip_prefixes = ["bump", "chore", "deps:", "dependabot", "ci:", "build:", "test:", "docs:", "style:", "refactor:"]
    title_lower = pr_title.lower().strip()

    for prefix in skip_prefixes:
        if title_lower.startswith(prefix):
            return True, f"PR di manutenzione ({prefix.rstrip(':')})"

    return False, None

def main():
    # Verifica variabili di ambiente
    required_env_vars = ["GH_TOKEN", "UPSTREAM_REPO", "FORK_REPO"]
    for var in required_env_vars:
        if not os.environ.get(var):
            print(f"Errore: Variabile di ambiente {var} non trovata")
            sys.exit(1)

    gh_token = os.environ["GH_TOKEN"]
    upstream_repo = os.environ["UPSTREAM_REPO"]
    fork_repo = os.environ["FORK_REPO"]

    print(f"🔑 Token presente: {'✅' if gh_token else '❌'}")
    print(f"📋 Upstream: {upstream_repo}")
    print(f"📋 Fork: {fork_repo}")

    # Inizializza GitHub client
    try:
        g = Github(gh_token)

        # Test di autenticazione (opzionale - fallback se fallisce)
        try:
            user = g.get_user()
            print(f"👤 Autenticato come: {user.login}")
        except GithubException as e:
            print(f"⚠️  Impossibile ottenere info utente (permessi limitati): {e.status}")
            print(f"📝 Continuando comunque...")

        upstream = g.get_repo(upstream_repo)
        fork = g.get_repo(fork_repo)

        # Testa l'accesso ai repository
        try:
            print(f"📊 Upstream: {upstream.full_name} (privato: {upstream.private})")
        except GithubException as e:
            print(f"❌ Errore accesso upstream repository: {e}")
            sys.exit(1)

        try:
            print(f"📊 Fork: {fork.full_name} (privato: {fork.private})")
        except GithubException as e:
            print(f"❌ Errore accesso fork repository: {e}")
            sys.exit(1)

    except GithubException as e:
        print(f"❌ Errore nell'inizializzazione GitHub client: {e}")
        sys.exit(1)

    # Ottieni il branch di default del fork
    try:
        default_branch = fork.default_branch
        print(f"🌳 Branch di default del fork: {default_branch}")
    except GithubException as e:
        print(f"⚠️  Errore nell'ottenere il branch di default: {e}")
        default_branch = "main"  # fallback

    print(f"\n🔄 Replicando PR da {upstream_repo} a {fork_repo}")

    # Trova PRs aperte nell'upstream
    try:
        upstream_prs = list(upstream.get_pulls(state="open"))
        print(f"📋 Trovate {len(upstream_prs)} PR aperte nell'upstream")
    except GithubException as e:
        print(f"❌ Errore nell'ottenere le PR dell'upstream: {e}")
        sys.exit(1)

    if len(upstream_prs) == 0:
        print("ℹ️  Nessuna PR aperta trovata nell'upstream")
        return

    replicated_count = 0
    skipped_count = 0
    error_count = 0

    for pr in upstream_prs:
        try:
            branch_name = pr.head.ref
            pr_title = pr.title
            pr_author = pr.user.login

            print(f"\n🔍 Processando PR #{pr.number}: {pr_title}")
            print(f"    📝 Branch: {branch_name}")
            print(f"    👤 Autore: {pr_author}")
            print(f"    🏠 Repository: {pr.head.repo.full_name if pr.head.repo else 'rimosso'}")

            # Verifica se la PR deve essere saltata
            should_skip, skip_reason = should_skip_pr(pr_title)
            if should_skip:
                print(f"  ⏭️  Saltando PR: {skip_reason}")
                skipped_count += 1
                continue

            # Controlla se la PR è già stata replicata nel fork
            try:
                existing_prs = [p for p in fork.get_pulls(state="all")
                              if p.title.startswith(f"Replica: {pr_title}") or
                                 p.head.ref == branch_name]
            except GithubException as e:
                print(f"  ⚠️  Errore nel controllare PR esistenti: {e}")
                existing_prs = []

            if existing_prs:
                print(f"  ⏭️  PR già replicata, saltando...")
                skipped_count += 1
                continue

            # Verifica se il branch esiste già nel fork (con il nuovo naming)
            source_repo_name = pr.head.repo.full_name.replace('/', '-') if pr.head.repo else 'unknown-repo'
            fork_branch_name = f"{source_repo_name}-{branch_name}"

            if check_branch_exists_in_fork(fork, fork_branch_name):
                print(f"  ⚠️  Branch {fork_branch_name} già esistente nel fork, saltando...")
                skipped_count += 1
                continue

            # Crea directory temporanea per il clone
            with tempfile.TemporaryDirectory() as temp_dir:
                repo_dir = os.path.join(temp_dir, "repo")

                # URL per il clone
                clone_url = get_clone_url(pr, gh_token)

                # URL del fork con autenticazione
                fork_url = f"https://{gh_token}@github.com/{fork_repo}.git"

                # Prepara il branch di replica (solo i commit della PR originale)
                ok, upstream_only_count, substituted_count = prepare_replica_branch(clone_url, repo_dir, branch_name, fork_url, default_branch, gh_token, pr, fork_branch_name)
                if not ok:
                    print(f"  ❌ Errore nella preparazione del branch di replica")
                    error_count += 1
                    continue

            # Crea una nuova PR nel fork
            print(f"  🔃 Creando PR nel fork...")

            # Nota di scope: traccia la divergenza upstream senza replicarla
            scope_note = ""
            if upstream_only_count:
                scope_note = f"""
⚠️ **Nota di scope:** sono stati replicati SOLO i commit della PR originale. Il main upstream è {upstream_only_count} commit avanti rispetto alla base di questa replica ({pr.base.sha[:7] if pr.base.sha else 'N/A'}): gli aggiornamenti del main upstream NON sono inclusi (scope diverso), la divergenza viene solo tracciata."""

            substitutions_note = ""
            if substituted_count:
                substitutions_note = f"""
🔧 **Nota sostituzioni:** {substituted_count} file della replica contenevano riferimenti all'infrastruttura upstream (es. immagine ghcr): sostituiti automaticamente per non rompere la CI del fork."""

            pr_body = f"""Questa PR replica la PR originale: {pr.html_url}

**Autore originale:** @{pr_author}
**Branch originale:** `{branch_name}`
**Repository originale:** {pr.head.repo.full_name if pr.head.repo else 'repository originale rimosso'}

---

{pr.body or 'Nessuna descrizione fornita.'}{scope_note}{substitutions_note}"""

            try:
                new_pr = fork.create_pull(
                    title=f"Replica: {pr_title}",
                    body=pr_body,
                    head=fork_branch_name,  # Usa il nuovo nome del branch
                    base=default_branch
                )
                print(f"  ✅ PR creata: {new_pr.html_url}")
                replicated_count += 1

                # Aggiungi etichette se possibile
                try:
                    # Controlla se le etichette esistono prima di aggiungerle
                    existing_labels = [label.name for label in fork.get_labels()]
                    labels_to_add = []

                    if "replica" in existing_labels:
                        labels_to_add.append("replica")
                    if "upstream" in existing_labels:
                        labels_to_add.append("upstream")

                    if labels_to_add:
                        new_pr.add_to_labels(*labels_to_add)
                        print(f"  🏷️  Etichette aggiunte: {', '.join(labels_to_add)}")
                    else:
                        print(f"  ℹ️  Nessuna etichetta disponibile da aggiungere")

                except GithubException as e:
                    print(f"  ⚠️  Impossibile aggiungere etichette: {e}")

            except GithubException as e:
                print(f"  ❌ Errore nella creazione della PR: {e}")
                # Se l'errore è di permessi, potrebbe essere utile continuare
                if e.status == 403:
                    print(f"  📝 Errore di permessi - verifica il token REPO_ACCESS_TOKEN")
                error_count += 1
                continue

        except GithubException as e:
            print(f"  ❌ Errore GitHub nel processare la PR {pr.number}: {e}")
            error_count += 1
            continue
        except Exception as e:
            print(f"  ❌ Errore generico nel processare la PR {pr.number}: {e}")
            error_count += 1
            continue

    print(f"\n📊 Riepilogo finale:")
    print(f"  ✅ PR replicate: {replicated_count}")
    print(f"  ⏭️  PR saltate: {skipped_count}")
    print(f"  ❌ Errori: {error_count}")
    print(f"  📝 Totale processate: {len(upstream_prs)}")

    # Non uscire con errore se ci sono solo alcuni errori
    if error_count > 0 and replicated_count == 0:
        print("⚠️  Nessuna PR replicata con successo")
        sys.exit(1)
    elif error_count > 0:
        print("⚠️  Alcuni errori ma almeno una PR replicata")

if __name__ == "__main__":
    main()
