# Stand-in for S3.
locals {
  seaweedfs_image = "chrislusf/seaweedfs:4.52"
  s3_port         = 8333
  s3_access_key   = "airflow"
  logs_bucket     = "airflow-logs"
  seaweedfs_ns    = kubernetes_namespace_v1.platform.metadata[0].name
  seaweedfs_host  = "seaweedfs.${local.seaweedfs_ns}.svc"
}

resource "random_password" "s3" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "s3" {
  metadata {
    name      = "seaweedfs-s3"
    namespace = local.seaweedfs_ns
  }
  data = {
    AWS_ACCESS_KEY_ID     = local.s3_access_key
    AWS_SECRET_ACCESS_KEY = random_password.s3.result
  }
}

resource "kubernetes_service_v1" "seaweedfs" {
  metadata {
    name      = "seaweedfs"
    namespace = local.seaweedfs_ns
  }
  spec {
    selector = { app = "seaweedfs" }
    port {
      name = "s3"
      port = local.s3_port
    }
  }
}

resource "kubernetes_stateful_set_v1" "seaweedfs" {
  metadata {
    name      = "seaweedfs"
    namespace = local.seaweedfs_ns
  }
  spec {
    service_name = kubernetes_service_v1.seaweedfs.metadata[0].name
    replicas     = 1
    selector {
      match_labels = { app = "seaweedfs" }
    }
    template {
      metadata {
        labels = { app = "seaweedfs" }
      }
      spec {
        container {
          name  = "seaweedfs"
          image = local.seaweedfs_image
          # The image's entrypoint stores data in /data and creates the bucket on startup.
          args = ["mini", "-bucket=${local.logs_bucket}"]
          env_from {
            secret_ref {
              name = kubernetes_secret_v1.s3.metadata[0].name
            }
          }
          port {
            container_port = local.s3_port
          }
          readiness_probe {
            http_get {
              path = "/healthz"
              port = local.s3_port
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

output "s3" {
  value = {
    endpoint   = "http://${local.seaweedfs_host}:${local.s3_port}"
    access_key = local.s3_access_key
    secret_key = random_password.s3.result
    bucket     = local.logs_bucket
  }
  sensitive = true
}
