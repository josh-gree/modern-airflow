#!/usr/bin/env bash
# Publishes dags/ to the in-cluster Gitea repo, creating the repo and its
# read-only user on first run. Airflow picks up the new commit on its own.
set -euo pipefail

cd "$(dirname "$0")/.."
export KUBECONFIG="$PWD/.kube/config"

tf_gitea() { terraform -chdir=infra/02-platform output -json gitea | python3 -c "import sys,json; print(json.load(sys.stdin)['$1'])"; }
admin_user=$(tf_gitea admin_user)
admin_password=$(tf_gitea admin_password)
reader_user=$(tf_gitea reader_user)
reader_password=$(tf_gitea reader_password)

port=13000
base="http://localhost:$port"
work=$(mktemp -d)

kubectl -n platform port-forward svc/gitea-http "$port:3000" >/dev/null &
forward=$!
trap 'kill "$forward" 2>/dev/null || true; rm -rf "$work"' EXIT

for _ in $(seq 1 30); do
  curl -sf -o /dev/null "$base/api/healthz" && break
  sleep 1
done

# Calls the Gitea API, failing unless the status is one of the allowed codes.
api() {
  local allowed=$1 method=$2 path=$3 body=$4 code
  code=$(curl -s -o /dev/null -w '%{http_code}' -u "$admin_user:$admin_password" \
    -H 'content-type: application/json' -X "$method" -d "$body" "$base/api/v1$path")
  [[ " $allowed " == *" $code "* ]] || { echo "gitea $method $path returned $code" >&2; exit 1; }
}

api "201 422" POST /admin/users \
  "{\"username\":\"$reader_user\",\"password\":\"$reader_password\",\"email\":\"$reader_user@airflow.local\",\"must_change_password\":false}"
api "201 409" POST /user/repos '{"name":"dags","private":true,"auto_init":true,"default_branch":"main"}'
api "204" PUT "/repos/$admin_user/dags/collaborators/$reader_user" '{"permission":"read"}'

git clone -q "http://$admin_user:$admin_password@localhost:$port/$admin_user/dags.git" "$work/repo"
rm -rf "$work/repo/dags"
cp -R dags "$work/repo/dags"
find "$work/repo/dags" -name __pycache__ -prune -exec rm -rf {} +

cd "$work/repo"
git add -A
if git diff --cached --quiet; then
  echo "dags unchanged"
else
  git -c user.name=dag-deploy -c user.email=dag-deploy@airflow.local commit -qm "Deploy dags"
  git push -q origin main
  echo "dags published: $(git rev-parse --short HEAD)"
fi
