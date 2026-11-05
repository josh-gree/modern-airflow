resource "random_id" "fernet" {
  byte_length = 32
}

resource "random_password" "api_secret" {
  length  = 64
  special = false
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "random_password" "admin" {
  length  = 24
  special = false
}

resource "kubernetes_secret_v1" "metadata" {
  metadata {
    name      = "airflow-metadata"
    namespace = local.namespace
  }
  data = { connection = local.sql_alchemy }
}

resource "kubernetes_secret_v1" "fernet" {
  metadata {
    name      = "airflow-fernet-key"
    namespace = local.namespace
  }
  # b64_url omits padding; Fernet requires it.
  data = { fernet-key = "${random_id.fernet.b64_url}=" }
}

resource "kubernetes_secret_v1" "api" {
  metadata {
    name      = "airflow-api-secret-key"
    namespace = local.namespace
  }
  data = { api-secret-key = random_password.api_secret.result }
}

resource "kubernetes_secret_v1" "jwt" {
  metadata {
    name      = "airflow-jwt-secret"
    namespace = local.namespace
  }
  data = { jwt-secret = random_password.jwt_secret.result }
}

# Connections live in the environment, so nothing is entered through the UI.
resource "kubernetes_secret_v1" "connections" {
  metadata {
    name      = "airflow-connections"
    namespace = local.namespace
  }
  data = {
    AIRFLOW_CONN_GIT_DAGS = jsonencode({
      conn_type = "git"
      host      = local.gitea.repo_url
      login     = local.gitea.reader_user
      password  = local.gitea.reader_password
    })
    AIRFLOW_CONN_LOG_STORE = jsonencode({
      conn_type = "aws"
      login     = local.minio.access_key
      password  = local.minio.secret_key
      extra = {
        endpoint_url  = local.minio.endpoint
        region_name   = "us-east-1"
        config_kwargs = { s3 = { addressing_style = "path" } }
      }
    })
  }
}

output "admin_password" {
  value     = random_password.admin.result
  sensitive = true
}
