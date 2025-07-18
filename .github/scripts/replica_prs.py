import os
import sys
import subprocess
import tempfile
import shutil
from github import Github
from github.GithubException import GithubException

def run_git_command(command, cwd=None):
    """Esegue un comando git e gestisce gli errori"""
    try:
        result = subprocess.run(
            command,
            shell=True,
            cwd=cwd,
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Errore nell'esecuzione del comando git: {command}")
        print(f"Errore: {e.stderr}")
        return None

def check_branch_exists_in_fork(fork, branch_name):
    """Verifica se un branch esiste già nel fork"""
    try:
        fork.get_branch(branch_name)
        return True
    except GithubException:
        return False

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

    # Inizializza GitHub client
    try:
        g = Github(gh_token)
        upstream = g.get_repo(upstream_repo)
        fork = g.get_repo(fork_repo)
    except GithubException as e:
        print(f"Errore nell'autenticazione o accesso ai repository: {e}")
        sys.exit(1)

    # Ottieni il branch di default del fork
    try:
        default_branch = fork.default_branch
        print(f"Branch di default del fork: {default_branch}")
    except GithubException as e:
        print(f"Errore nell'ottenere il branch di default: {e}")
        default_branch = "main"  # fallback

    print(f"Replicando PR da {upstream_repo} a {fork_repo}")

    # Trova PRs aperte nell'upstream
    try:
        upstream_prs = list(upstream.get_pulls(state="open"))
        print(f"Trovate {len(upstream_prs)} PR aperte nell'upstream")
    except GithubException as e:
        print(f"Errore nell'ottenere le PR dell'upstream: {e}")
        sys.exit(1)

    replicated_count = 0
    skipped_count = 0

    for pr in upstream_prs:
        try:
            branch_name = pr.head.ref
            pr_title = pr.title
            pr_author = pr.user.login

            print(f"\nProcessando PR: {pr_title} (branch: {branch_name})")

            # Controlla se la PR è già stata replicata nel fork
            existing_prs = [p for p in fork.get_pulls(state="all")
                          if p.title.startswith(f"Replica: {pr_title}") or
                             p.head.ref == branch_name]

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

                # URL autenticato per il clone
                if pr.head.repo.private:
                    clone_url = f"https://{gh_token}@github.com/{pr.head.repo.full_name}.git"
                else:
                    clone_url = pr.head.repo.clone_url

                print(f"  📥 Clonando repository...")
                if not run_git_command(f"git clone {clone_url} {repo_dir}"):
                    print(f"  ❌ Errore nel clone del repository")
                    continue

                # Checkout del branch della PR
                print(f"  🔄 Checkout del branch {branch_name}...")
                if not run_git_command(f"git checkout {branch_name}", cwd=repo_dir):
                    print(f"  ❌ Errore nel checkout del branch {branch_name}")
                    continue

                # Aggiungi remote del fork con autenticazione
                fork_url = f"https://{gh_token}@github.com/{fork_repo}.git"
                if not run_git_command(f"git remote add fork {fork_url}", cwd=repo_dir):
                    print(f"  ❌ Errore nell'aggiungere il remote del fork")
                    continue

                # Push del branch al fork
                print(f"  📤 Push del branch al fork...")
                if not run_git_command(f"git push fork {branch_name}", cwd=repo_dir):
                    print(f"  ❌ Errore nel push del branch al fork")
                    continue

            # Crea una nuova PR nel fork
            print(f"  🔃 Creando PR nel fork...")
            pr_body = f"""Questa PR replica la PR originale: {pr.html_url}

**Autore originale:** @{pr_author}
**Branch originale:** `{branch_name}`

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
                    labels = ["replica", "upstream"]
                    new_pr.add_to_labels(*labels)
                except GithubException:
                    # Ignora errori di etichette (potrebbero non esistere)
                    pass

            except GithubException as e:
                print(f"  ❌ Errore nella creazione della PR: {e}")
                continue

        except GithubException as e:
            print(f"  ❌ Errore nel processare la PR {pr.number}: {e}")
            continue
        except Exception as e:
            print(f"  ❌ Errore generico nel processare la PR {pr.number}: {e}")
            continue

    print(f"\n📊 Riepilogo:")
    print(f"  ✅ PR replicate: {replicated_count}")
    print(f"  ⏭️  PR saltate: {skipped_count}")
    print(f"  📝 Totale processate: {len(upstream_prs)}")

if __name__ == "__main__":
    main()
