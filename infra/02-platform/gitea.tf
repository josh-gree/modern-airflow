# Stand-in for GitHub. scripts/push-dags.sh creates the repo and read-only user.
resource "random_password" "gitea_admin" {
  length  = 32
  special = false
}

resource "random_password" "gitea_reader" {
  length  = 32
  special = false
}

resource "helm_release" "gitea" {
  name       = "gitea"
  namespace  = kubernetes_namespace_v1.platform.metadata[0].name
  repository = "https://dl.gitea.com/charts"
  chart      = "gitea"
  version    = "12.7.0"
  wait       = true
  timeout    = 300

  values = [yamlencode({
    "valkey-cluster" = { enabled = false }
    valkey           = { enabled = false }
    postgresql       = { enabled = false }
    "postgresql-ha"  = { enabled = false }
    persistence      = { size = "1Gi" }
    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
      limits   = { memory = "512Mi" }
    }
    gitea = {
      admin = {
        username = "gitadmin"
        password = random_password.gitea_admin.result
        email    = "gitadmin@airflow.local"
      }
      config = {
        database = { DB_TYPE = "sqlite3" }
        session  = { PROVIDER = "memory" }
        cache    = { ADAPTER = "memory" }
        queue    = { TYPE = "level" }
      }
    }
  })]
}

output "gitea" {
  value = {
    repo_url        = "http://gitea-http.${kubernetes_namespace_v1.platform.metadata[0].name}.svc:3000/gitadmin/dags.git"
    admin_user      = "gitadmin"
    admin_password  = random_password.gitea_admin.result
    reader_user     = "airflow-reader"
    reader_password = random_password.gitea_reader.result
  }
  sensitive = true
}
