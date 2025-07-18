import os
import sys
import subprocess
import tempfile
import shutil
from github import Github
from github.GithubException import GithubException
import time

def run_git_command(command, cwd=None, timeout=300):
    """Esegue un comando git e gestisce gli errori"""
    try:
        # Masking del token per il logging
        safe_command = command.replace(os.environ.get("GH_TOKEN", ""), "***") if "GH_TOKEN" in os.environ else command
        print(f"    🔧 Eseguendo: {safe_command}")

        result = subprocess.run(
            command,
            shell=True,
            cwd=cwd,
            capture_output=True,
            text=True,
            check=True,
            timeout=timeout
        )
        if result.stdout:
            # Tronca output molto lungo
            output_preview = result.stdout.strip()
            if len(output_preview) > 200:
                output_preview = output_preview[:200] + "..."
            print(f"    📤 Output: {output_preview}")
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        safe_command = command.replace(os.environ.get("GH_TOKEN", ""), "***") if "GH_TOKEN" in os.environ else command
        print(f"    ❌ Errore nell'esecuzione del comando git: {safe_command}")
        print(f"    📝 Stderr: {e.stderr}")
        print(f"    📝 Stdout: {e.stdout}")
        print(f"    📝 Return code: {e.returncode}")
        return None
    except subprocess.TimeoutExpired:
        safe_command = command.replace(os.environ.get("GH_TOKEN", ""), "***") if "GH_TOKEN" in os.environ else command
        print(f"    ⏰ Timeout nell'esecuzione del comando: {safe_command}")
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

def get_clone_url(pr, gh_token):
    """Genera l'URL di clone appropriato basato sul tipo di repository"""
    repo = pr.head.repo

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

def verify_repository_access(repo, gh_token):
    """Verifica l'accesso al repository e fornisce informazioni diagnostiche"""
    try:
        print(f"  🔍 Verificando accesso al repository: {repo.full_name}")
        print(f"    - Privato: {repo.private}")
        print(f"    - Fork: {repo.fork}")
        print(f"    - Proprietario: {repo.owner.login}")
        print(f"    - URL clone: {repo.clone_url}")
        print(f"    - URL SSH: {repo.ssh_url}")

        # Verifica permessi
        permissions = repo.permissions
        print(f"    - Permessi: admin={permissions.admin}, push={permissions.push}, pull={permissions.pull}")

        return True
    except GithubException as e:
        print(f"  ❌ Errore verifica repository: {e}")
        print(f"    - Status: {e.status}")
        print(f"    - Data: {e.data}")
        return False

def clone_and_setup_repo(clone_url, repo_dir, branch_name, fork_url, gh_token, pr):
    """Clona il repository e configura i remote"""

    # Step 0: Verifica accesso al repository sorgente
    print(f"  🔍 Diagnostica repository sorgente...")
    if not verify_repository_access(pr.head.repo, gh_token):
        print(f"  ❌ Impossibile accedere al repository sorgente")
        return False

    # Step 1: Clone del repository con multiple strategie
    print(f"  📥 Clonando da: {clone_url.replace(gh_token, '***') if gh_token in clone_url else clone_url}")

    # Strategia 1: Clone shallow con branch specifico
    clone_command = f"git clone --depth=1 --single-branch --branch {branch_name} '{clone_url}' '{repo_dir}'"
    success = run_git_command(clone_command, timeout=180)

    if not success:
        print(f"  🔄 Fallback 1: Clone completo con checkout...")
        # Rimuovi directory se esiste parzialmente
        if os.path.exists(repo_dir):
            shutil.rmtree(repo_dir)

        # Strategia 2: Clone completo poi checkout
        clone_command = f"git clone '{clone_url}' '{repo_dir}'"
        if not run_git_command(clone_command, timeout=300):
            print(f"  🔄 Fallback 2: Tentativo senza autenticazione...")

            # Strategia 3: Se il repo è pubblico, prova senza token
            if clone_url.startswith("https://") and "@github.com" in clone_url:
                public_url = clone_url.split("@github.com/")[1]
                public_url = f"https://github.com/{public_url}"
                print(f"  🌐 Tentativo con URL pubblico: {public_url}")

                if os.path.exists(repo_dir):
                    shutil.rmtree(repo_dir)

                if not run_git_command(f"git clone '{public_url}' '{repo_dir}'", timeout=300):
                    print(f"  🔄 Fallback 3: Verifica esistenza repository...")

                    # Strategia 4: Verifica se il repository esiste via API
                    try:
                        import requests
                        api_url = f"https://api.github.com/repos/{pr.head.repo.full_name}"
                        headers = {"Authorization": f"token {gh_token}"}
                        response = requests.get(api_url, headers=headers, timeout=30)

                        if response.status_code == 404:
                            print(f"  ❌ Repository {pr.head.repo.full_name} non trovato o non accessibile")
                            return False
                        elif response.status_code == 403:
                            print(f"  ❌ Accesso negato al repository {pr.head.repo.full_name}")
                            return False
                        else:
                            print(f"  ℹ️  Repository esiste (status: {response.status_code}), ma clone fallito")

                    except Exception as e:
                        print(f"  ⚠️  Errore nella verifica API: {e}")

                    print(f"  ❌ Tutti i tentativi di clone falliti")
                    return False

        # Checkout del branch se necessario
        current_branch = run_git_command("git branch --show-current", cwd=repo_dir)
        if current_branch != branch_name:
            print(f"  🔄 Checkout branch {branch_name}...")
            if not run_git_command(f"git checkout {branch_name}", cwd=repo_dir):
                # Prova fetch + checkout
                print(f"  🔄 Fetch del branch {branch_name}...")
                if not run_git_command(f"git fetch origin {branch_name}:{branch_name}", cwd=repo_dir):
                    # Ultima chance: fetch all branches e poi checkout
                    print(f"  🔄 Fetch completo dei branch...")
                    run_git_command("git fetch --all", cwd=repo_dir)

                # Lista tutti i branch disponibili per debug
                branches = run_git_command("git branch -a", cwd=repo_dir)
                print(f"  📋 Branch disponibili: {branches}")

                if not run_git_command(f"git checkout {branch_name}", cwd=repo_dir):
                    # Prova con origin/ prefix
                    if not run_git_command(f"git checkout origin/{branch_name}", cwd=repo_dir):
                        print(f"  ❌ Impossibile fare checkout del branch {branch_name}")
                        return False

    # Step 2: Configura git
    setup_git_config(repo_dir)

    # Step 3: Verifica stato del repository
    print(f"  🔍 Verifica stato repository...")
    current_branch = run_git_command("git branch --show-current", cwd=repo_dir)
    if current_branch != branch_name:
        print(f"  ⚠️  Branch corrente ({current_branch}) diverso da quello richiesto ({branch_name})")
        # Non fallire se siamo su un branch correlato (es. origin/branch)
        if f"origin/{branch_name}" not in current_branch and branch_name not in current_branch:
            return False

    # Step 4: Aggiungi remote del fork
    print(f"  🔗 Aggiungendo remote fork...")
    # Controlla se remote fork esiste già
    remotes = run_git_command("git remote -v", cwd=repo_dir)
    if remotes and "fork" not in remotes:
        if not run_git_command(f"git remote add fork '{fork_url}'", cwd=repo_dir):
            print(f"  ⚠️  Errore nell'aggiungere remote fork, continuando...")
    else:
        print(f"  ℹ️  Remote fork già presente o comando remotes fallito")

    # Step 5: Push del branch al fork
    print(f"  📤 Push del branch {branch_name} al fork...")
    push_command = f"git push fork {current_branch}:{branch_name}"
    if not run_git_command(push_command, cwd=repo_dir, timeout=180):
        # Prova force push se c'è un conflitto
        print(f"  🔄 Tentativo con force push...")
        if not run_git_command(f"git push --force fork {current_branch}:{branch_name}", cwd=repo_dir, timeout=180):
            print(f"  ❌ Push al fork fallito")
            return False

    print(f"  ✅ Repository configurato e push completato")
    return True

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
            print(f"    🏠 Repository: {pr.head.repo.full_name}")

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

            # Verifica se il branch esiste già nel fork
            if check_branch_exists_in_fork(fork, branch_name):
                print(f"  ⚠️  Branch {branch_name} già esistente nel fork, saltando...")
                skipped_count += 1
                continue

            # Crea directory temporanea per il clone
            with tempfile.TemporaryDirectory() as temp_dir:
                repo_dir = os.path.join(temp_dir, "repo")

                # URL per il clone
                clone_url = get_clone_url(pr, gh_token)

                # URL del fork con autenticazione
                fork_url = f"https://{gh_token}@github.com/{fork_repo}.git"

                # Clona e configura il repository
                if not clone_and_setup_repo(clone_url, repo_dir, branch_name, fork_url, gh_token, pr):
                    print(f"  ❌ Errore nella configurazione del repository")
                    error_count += 1
                    continue

            # Crea una nuova PR nel fork
            print(f"  🔃 Creando PR nel fork...")
            pr_body = f"""Questa PR replica la PR originale: {pr.html_url}

**Autore originale:** @{pr_author}
**Branch originale:** `{branch_name}`
**Repository originale:** {pr.head.repo.full_name}

---

{pr.body or 'Nessuna descrizione fornita.'}"""

            try:
                new_pr = fork.create_pull(
                    title=f"Replica: {pr_title}",
                    body=pr_body,
                    head=branch_name,
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
