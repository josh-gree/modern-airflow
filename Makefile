export KUBECONFIG := $(CURDIR)/.kube/config

CLUSTER := airflow
IMAGE   := local/airflow
TAG     := $(shell shasum image/Dockerfile | cut -c1-12)
MINIO   := minio/minio:RELEASE.2025-04-08T15-41-24Z minio/mc:RELEASE.2025-04-08T15-39-49Z
TF      := terraform -chdir=infra

.PHONY: up down cluster platform image dags airflow ui password status

up: cluster platform image dags airflow

cluster:
	$(TF)/01-cluster init -input=false
	$(TF)/01-cluster apply -auto-approve -input=false
	kind load docker-image $(MINIO) --name $(CLUSTER)

platform:
	$(TF)/02-platform init -input=false
	$(TF)/02-platform apply -auto-approve -input=false

image:
	docker build -t $(IMAGE):$(TAG) image
	kind load docker-image $(IMAGE):$(TAG) --name $(CLUSTER)

dags:
	./scripts/push-dags.sh

airflow:
	$(TF)/03-airflow init -input=false
	$(TF)/03-airflow apply -auto-approve -input=false -var image_tag=$(TAG)

# The cluster holds all the other state, so deleting it is the whole teardown.
down:
	$(TF)/01-cluster destroy -auto-approve -input=false
	rm -f infra/02-platform/terraform.tfstate* infra/03-airflow/terraform.tfstate*

ui:
	@echo "http://localhost:8080  user: admin  password: make password"
	kubectl -n airflow port-forward svc/airflow-api-server 8080:8080

password:
	@$(TF)/03-airflow output -raw admin_password

status:
	kubectl get nodes
	kubectl -n airflow get pods -o wide
