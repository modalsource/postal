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
        print(f"    🔧 Eseguendo: {command}")
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
            print(f"    📤 Output: {result.stdout[:200]}...")
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"    ❌ Errore nell'esecuzione del comando git: {command}")
        print(f"    📝 Stderr: {e.stderr}")
        print(f"    📝 Stdout: {e.stdout}")
        print(f"    📝 Return code: {e.returncode}")
        return None
    except subprocess.TimeoutExpired:
        print(f"    ⏰ Timeout nell'esecuzione del comando: {command}")
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

def clone_and_setup_repo(clone_url, repo_dir, branch_name, fork_url, gh_token):
    """Clona il repository e configura i remote"""

    # Step 1: Clone del repository
    print(f"  📥 Clonando da: {clone_url.replace(gh_token, '***') if gh_token in clone_url else clone_url}")

    clone_command = f"git clone --depth=1 --single-branch --branch {branch_name} {clone_url} {repo_dir}"
    if not run_git_command(clone_command, timeout=180):
        # Fallback: clone completo e poi checkout
        print(f"  🔄 Tentativo fallback con clone completo...")
        clone_command = f"git clone {clone_url} {repo_dir}"
        if not run_git_command(clone_command, timeout=300):
            return False

        # Checkout del branch
        if not run_git_command(f"git checkout {branch_name}", cwd=repo_dir):
            # Prova a fare fetch del branch se non esiste localmente
            if not run_git_command(f"git fetch origin {branch_name}:{branch_name}", cwd=repo_dir):
                return False
            if not run_git_command(f"git checkout {branch_name}", cwd=repo_dir):
                return False

    # Step 2: Configura git
    setup_git_config(repo_dir)

    # Step 3: Aggiungi remote del fork
    print(f"  🔗 Aggiungendo remote fork...")
    if not run_git_command(f"git remote add fork {fork_url}", cwd=repo_dir):
        return False

    # Step 4: Verifica che siamo sul branch corretto
    current_branch = run_git_command("git branch --show-current", cwd=repo_dir)
    if current_branch != branch_name:
        print(f"  ⚠️  Branch corrente ({current_branch}) diverso da quello richiesto ({branch_name})")
        return False

    # Step 5: Push del branch al fork
    print(f"  📤 Push del branch {branch_name} al fork...")
    push_command = f"git push fork {branch_name}"
    if not run_git_command(push_command, cwd=repo_dir, timeout=180):
        # Prova force push se c'è un conflitto
        print(f"  🔄 Tentativo con force push...")
        if not run_git_command(f"git push --force fork {branch_name}", cwd=repo_dir, timeout=180):
            return False

    return True

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
                if not clone_and_setup_repo(clone_url, repo_dir, branch_name, fork_url, gh_token):
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
