.PHONY: help deploy diff rollback validate destroy status

ENV ?= dev
SERVICE ?= all

help:
	@echo "HiveMind Deployment Manager"
	@echo ""
	@echo "Usage:"
	@echo "  make deploy ENV=dev              - Deploy all services to dev"
	@echo "  make deploy ENV=prod SERVICE=auth-service - Deploy specific service"
	@echo "  make diff ENV=staging            - Show changes before deploy"
	@echo "  make rollback SERVICE=auth-service ENV=prod - Rollback service"
	@echo "  make validate ENV=dev            - Validate configuration"
	@echo "  make status ENV=dev              - Show deployment status"
	@echo "  make destroy ENV=dev             - Destroy environment"

deploy:
	@./scripts/deploy.sh $(ENV) $(SERVICE)

diff:
	@./scripts/diff.sh $(ENV)

rollback:
	@./scripts/rollback.sh $(SERVICE) $(ENV)

validate:
	@helmfile -e $(ENV) lint

status:
	@helmfile -e $(ENV) status

destroy:
	@helmfile -e $(ENV) destroy

sync:
	@helmfile -e $(ENV) sync
