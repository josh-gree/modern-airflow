terraform {
  required_version = ">= 1.14"
  required_providers {
    kind = { source = "tehcyx/kind", version = "~> 0.13" }
  }
}

variable "cluster_name" {
  type    = string
  default = "airflow"
}

variable "node_image" {
  type    = string
  default = "kindest/node:v1.36.4"
}

variable "worker_count" {
  type    = number
  default = 2
}

resource "kind_cluster" "this" {
  name            = var.cluster_name
  node_image      = var.node_image
  wait_for_ready  = true
  kubeconfig_path = abspath("${path.module}/../../.kube/config")

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"
    }

    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"
      }
    }
  }
}

output "kubeconfig_path" {
  value = kind_cluster.this.kubeconfig_path
}
