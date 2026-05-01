# hivemind-deployment

Helm charts, Helmfile orchestration, and environment configurations for deploying all HiveMind microservices to Kubernetes.

## Structure

```
hivemind-deployment/
├── charts/                 # 12 Helm charts
│   ├── eureka-server/
│   ├── config-server/
│   ├── api-gateway/
│   ├── auth-service/
│   ├── user-service/
│   ├── group-service/
│   ├── post-service/
│   ├── meeting-service/
│   ├── notification-service/
│   ├── media-service/
│   ├── frontend/
│   └── zipkin/
├── environments/           # Per-environment values
│   ├── dev/
│   ├── staging/
│   └── prod/
├── helmfile.d/             # Helmfile orchestration
│   ├── 00-infrastructure.yaml
│   ├── 01-platform.yaml
│   ├── 02-services.yaml
│   └── 03-monitoring.yaml
├── helmfile.yaml           # Root helmfile
└── Makefile                # Deployment commands
```

## Usage

```bash
# Deploy to dev
make deploy ENV=dev

# Deploy to production
make deploy ENV=prod

# Show diff before deploying
make diff ENV=staging

# Check status
make status ENV=dev

# Rollback a service
make rollback SERVICE=auth-service ENV=prod
```

## Prerequisites

- Kubernetes cluster
- Helm 3.14+
- Helmfile 0.162+
- kubectl configured

## Related Repos

- [hivemind-backend](https://github.com/AhmedNijim92/hivemind-backend) — Main monorepo
- [hivemind-common](https://github.com/AhmedNijim92/hivemind-common) — Shared DTOs
- [hivemind-frontend](https://github.com/AhmedNijim92/hivemind-frontend) — Next.js frontend
