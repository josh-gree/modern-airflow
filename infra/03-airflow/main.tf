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

variable "image_repository" {
  type    = string
  default = "local/airflow"
}

variable "image_tag" {
  type = string
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

data "terraform_remote_state" "platform" {
  backend = "local"
  config = {
    path = "${path.module}/../02-platform/terraform.tfstate"
  }
}

locals {
  gitea = data.terraform_remote_state.platform.outputs.gitea
  minio = data.terraform_remote_state.platform.outputs.minio

  namespace   = kubernetes_namespace_v1.airflow.metadata[0].name
  db_cluster  = "airflow-db"
  db_pooler   = "${local.db_cluster}-pooler"
  db_name     = "airflow"
  db_user     = "airflow"
  db_host     = "${local.db_pooler}.${local.namespace}.svc"
  sql_alchemy = "postgresql+psycopg2://${local.db_user}:${random_password.db.result}@${local.db_host}:5432/${local.db_name}?sslmode=require"
}

resource "kubernetes_namespace_v1" "airflow" {
  metadata {
    name = "airflow"
  }
}
