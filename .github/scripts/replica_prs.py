import os
from github import Github

gh_token = os.environ["GH_TOKEN"]
upstream_repo = os.environ["UPSTREAM_REPO"]
fork_repo = os.environ["FORK_REPO"]

g = Github(gh_token)
upstream = g.get_repo(upstream_repo)
fork = g.get_repo(fork_repo)

# Trova PRs aperte nell'upstream
for pr in upstream.get_pulls(state="open"):
    branch_name = pr.head.ref
    remote_url = pr.head.repo.clone_url

    # Controlla se la PR è già stata replicata nel fork
    existing = [p for p in fork.get_pulls(state="open") if p.title == pr.title]
    if existing:
        continue

    # Clona il branch della PR e pushalo nel fork
    os.system(f"git clone {remote_url} tmprepo")
    os.chdir("tmprepo")
    os.system(f"git checkout {branch_name}")
    os.system(f"git remote add fork https://{gh_token}@github.com/{fork_repo}.git")
    os.system(f"git push fork {branch_name}")
    os.chdir("..")
    os.system("rm -rf tmprepo")

    # Crea una nuova PR nel fork
    fork.create_pull(
        title=f"Replica: {pr.title}",
        body=f"Questa PR replica la PR originale: {pr.html_url}\n\n{pr.body}",
        head=branch_name,
        base="main" # Cambia se il tuo default branch è diverso
    )