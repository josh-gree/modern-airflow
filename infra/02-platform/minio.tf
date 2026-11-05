# Stand-in for S3. MinIO no longer publishes community images, so these exact
# tags are loaded from the local Docker cache by `make cluster` and never pulled.
locals {
  minio_image = "minio/minio:RELEASE.2025-04-08T15-41-24Z"
  mc_image    = "minio/mc:RELEASE.2025-04-08T15-39-49Z"
  logs_bucket = "airflow-logs"
  minio_host  = "minio.${kubernetes_namespace_v1.platform.metadata[0].name}.svc"
  minio_ns    = kubernetes_namespace_v1.platform.metadata[0].name
}

resource "random_password" "minio" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "minio" {
  metadata {
    name      = "minio-root"
    namespace = local.minio_ns
  }
  data = {
    MINIO_ROOT_USER     = "airflow"
    MINIO_ROOT_PASSWORD = random_password.minio.result
  }
}

resource "kubernetes_service_v1" "minio" {
  metadata {
    name      = "minio"
    namespace = local.minio_ns
  }
  spec {
    selector = { app = "minio" }
    port {
      name = "s3"
      port = 9000
    }
  }
}

resource "kubernetes_stateful_set_v1" "minio" {
  metadata {
    name      = "minio"
    namespace = local.minio_ns
  }
  spec {
    service_name = kubernetes_service_v1.minio.metadata[0].name
    replicas     = 1
    selector {
      match_labels = { app = "minio" }
    }
    template {
      metadata {
        labels = { app = "minio" }
      }
      spec {
        container {
          name              = "minio"
          image             = local.minio_image
          image_pull_policy = "Never"
          args              = ["server", "/data"]
          env_from {
            secret_ref {
              name = kubernetes_secret_v1.minio.metadata[0].name
            }
          }
          port {
            container_port = 9000
          }
          readiness_probe {
            http_get {
              path = "/minio/health/ready"
              port = 9000
            }
          }
          resources {
            requests = { cpu = "50m", memory = "256Mi" }
            limits   = { memory = "512Mi" }
          }
          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }
      }
    }
    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = { storage = "2Gi" }
        }
      }
    }
  }
}

resource "kubernetes_job_v1" "bucket" {
  metadata {
    name      = "minio-create-bucket"
    namespace = local.minio_ns
  }
  spec {
    backoff_limit = 6
    template {
      metadata {}
      spec {
        restart_policy = "OnFailure"
        container {
          name              = "mc"
          image             = local.mc_image
          image_pull_policy = "Never"
          command = ["sh", "-c", <<-EOT
            mc alias set s3 http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" &&
            mc mb --ignore-existing s3/${local.logs_bucket}
          EOT
          ]
          env_from {
            secret_ref {
              name = kubernetes_secret_v1.minio.metadata[0].name
            }
          }
        }
      }
    }
  }
  wait_for_completion = true
  depends_on          = [kubernetes_stateful_set_v1.minio]
}

output "minio" {
  value = {
    endpoint   = "http://${local.minio_host}:9000"
    access_key = "airflow"
    secret_key = random_password.minio.result
    bucket     = local.logs_bucket
  }
  sensitive = true
}
