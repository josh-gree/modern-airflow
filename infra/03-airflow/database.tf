resource "random_password" "db" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "db_owner" {
  metadata {
    name      = "${local.db_cluster}-owner"
    namespace = local.namespace
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = local.db_user
    password = random_password.db.result
  }
}

resource "kubernetes_manifest" "db_cluster" {
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Cluster"
    metadata = {
      name      = local.db_cluster
      namespace = local.namespace
    }
    spec = {
      instances = 2
      bootstrap = {
        initdb = {
          database = local.db_name
          owner    = local.db_user
          secret   = { name = kubernetes_secret_v1.db_owner.metadata[0].name }
        }
      }
      storage = { size = "2Gi" }
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }
  }

  wait {
    condition {
      type   = "Ready"
      status = "True"
    }
  }

  timeouts {
    create = "5m"
    update = "5m"
  }
}

resource "kubernetes_manifest" "db_pooler" {
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Pooler"
    metadata = {
      name      = local.db_pooler
      namespace = local.namespace
    }
    spec = {
      cluster   = { name = local.db_cluster }
      instances = 2
      type      = "rw"
      pgbouncer = {
        poolMode = "transaction"
        parameters = {
          max_client_conn   = "500"
          default_pool_size = "20"
          # Airflow's async API paths use asyncpg, which relies on prepared statements.
          max_prepared_statements = "200"
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.db_cluster]
}
