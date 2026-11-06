locals {
  small  = { requests = { cpu = "100m", memory = "384Mi" }, limits = { memory = "1Gi" } }
  medium = { requests = { cpu = "200m", memory = "512Mi" }, limits = { memory = "1536Mi" } }
}

resource "helm_release" "airflow" {
  name       = "airflow"
  namespace  = local.namespace
  repository = "https://airflow.apache.org"
  chart      = "airflow"
  version    = "1.22.0"
  wait       = true
  timeout    = 600

  values = [yamlencode({
    executor = "KubernetesExecutor"

    images = {
      airflow = {
        repository = var.image_repository
        tag        = var.image_tag
        pullPolicy = "IfNotPresent"
      }
    }

    postgresql = { enabled = false }
    data       = { metadataSecretName = kubernetes_secret_v1.metadata.metadata[0].name }

    fernetKeySecretName    = kubernetes_secret_v1.fernet.metadata[0].name
    apiSecretKeySecretName = kubernetes_secret_v1.api.metadata[0].name
    jwtSecretName          = kubernetes_secret_v1.jwt.metadata[0].name

    # Without this, helm's --wait deadlocks: pods wait for migrations,
    # and a hook-based migration job waits for the pods.
    migrateDatabaseJob = { useHelmHooks = false, applyCustomEnv = false }
    createUserJob = {
      useHelmHooks   = false
      applyCustomEnv = false
      defaultUser    = { password = random_password.admin.result }
    }

    scheduler = { replicas = 1, resources = local.medium }
    apiServer = { replicas = 1, resources = local.medium }
    dagProcessor = {
      enabled   = true
      replicas  = 1
      resources = local.small
      dagBundleConfigList = [{
        name      = "dags"
        classpath = "airflow.providers.git.bundles.git.GitDagBundle"
        kwargs = {
          git_conn_id      = "git_dags"
          tracking_ref     = "main"
          subdir           = "dags"
          refresh_interval = 30
        }
      }]
    }
    triggerer = {
      replicas    = 1
      resources   = local.small
      persistence = { size = "1Gi" }
    }
    workers = { resources = local.small }

    statsd = { enabled = false }

    extraEnvFrom = yamlencode([{
      secretRef = { name = kubernetes_secret_v1.connections.metadata[0].name }
    }])

    config = {
      api = { workers = 2 }
      logging = {
        remote_logging         = "True"
        remote_log_conn_id     = "log_store"
        remote_base_log_folder = "s3://${local.s3.bucket}"
      }
    }
  })]

  depends_on = [kubernetes_manifest.db_pooler]
}
