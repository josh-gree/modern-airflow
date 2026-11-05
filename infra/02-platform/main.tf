# Operators, plus stand-ins for services production would get elsewhere (S3, GitHub).
# Operator CRDs must exist before 03-airflow can plan custom resources.
terraform {
  required_version = ">= 1.14"
  required_providers {
    helm       = { source = "hashicorp/helm", version = "~> 3.3" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.5" }
    random     = { source = "hashicorp/random", version = "~> 3.7" }
  }
}

variable "kubeconfig_path" {
  type    = string
  default = "../../.kube/config"
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

resource "helm_release" "cnpg" {
  name             = "cnpg"
  namespace        = "cnpg-system"
  create_namespace = true
  repository       = "https://cloudnative-pg.github.io/charts"
  chart            = "cloudnative-pg"
  version          = "0.29.1"
  wait             = true
  timeout          = 300
}

resource "kubernetes_namespace_v1" "platform" {
  metadata {
    name = "platform"
  }
}
