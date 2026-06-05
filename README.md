# hivemind-deployment

Production-grade Kubernetes deployment for the HiveMind microservices platform. Helm charts, Helmfile orchestration, environment configurations, security policies, and observability.

## Quick Start

```bash
# Deploy to dev
make deploy ENV=dev

# Deploy to production (preview first)
make diff ENV=prod
make deploy ENV=prod

# Rollback a service
make rollback SERVICE=auth-service ENV=prod

# Check status
make status ENV=prod
```

## Documentation

| Document | Description |
|----------|-------------|
| [Deployment Guide](docs/DEPLOYMENT-GUIDE.md) | Full operations guide — architecture, deploy order, environments, runbook, DR |
| [Security](docs/SECURITY.md) | Network policies, pod security, TLS, secrets, compliance checklist |
| [Chart Development](docs/CHART-DEVELOPMENT.md) | Template patterns, testing, versioning, adding new services |

## Structure

```
hivemind-deployment/
├── helmfile.yaml                    # Root orchestrator
├── helmfile.d/                      # Layered deployment
│   ├── 00-namespace.yaml           # Namespace + ResourceQuota + LimitRange
│   ├── 00-infrastructure.yaml      # Cassandra, Kafka, Redis, MongoDB, PostgreSQL
│   ├── 01-platform.yaml            # Eureka Server, Config Server
│   ├── 02-services.yaml            # All domain services + gateway + frontend
│   └── 03-monitoring.yaml          # Prometheus, Grafana, Zipkin, Alert Rules
├── charts/                          # 14 Helm charts
│   ├── namespace-setup/            # Namespace governance (quota, limits)
│   ├── prometheus-rules/           # PrometheusRule alerting
│   ├── eureka-server/
│   ├── config-server/
│   ├── api-gateway/                # + Ingress + NetworkPolicy
│   ├── auth-service/
│   ├── user-service/
│   ├── group-service/
│   ├── post-service/
│   ├── meeting-service/
│   ├── notification-service/
│   ├── media-service/
│   ├── frontend/                   # + Ingress
│   └── zipkin/
├── environments/
│   ├── dev/                        # 1 replica, standard storage
│   ├── staging/                    # 2 replicas, production-like
│   └── prod/                       # 3-5 replicas, fast-ssd, HA
├── scripts/
│   ├── deploy.sh
│   ├── rollback.sh
│   └── diff.sh
├── .sops.yaml                      # SOPS encryption rules
├── Makefile                         # CLI shortcuts
└── docs/                            # Documentation
```

## Production Features

| Feature | Status |
|---------|--------|
| Zero-downtime rolling updates | ✅ |
| Startup + liveness + readiness probes | ✅ |
| HPA (CPU-based autoscaling) | ✅ |
| PodDisruptionBudgets | ✅ |
| NetworkPolicies (gateway-only ingress) | ✅ |
| Pod security (non-root, drop ALL caps) | ✅ |
| Topology spread (multi-AZ) | ✅ |
| Ingress with TLS (cert-manager) | ✅ |
| Namespace ResourceQuota + LimitRange | ✅ |
| Dedicated ServiceAccounts | ✅ |
| Prometheus alerting rules | ✅ |
| SOPS secret encryption | ✅ |
| Atomic deploys (auto-rollback on fail) | ✅ |
| Distributed tracing (Zipkin) | ✅ |
| Revision history (rollback support) | ✅ |

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| kubectl | 1.28+ | Cluster interaction |
| Helm | 3.14+ | Chart installation |
| Helmfile | 0.162+ | Multi-chart orchestration |
| SOPS | 3.8+ | Secret encryption |
| age | 1.1+ | Encryption key |

## Related Repos

- [hivemind-backend](https://github.com/AhmedNijim92/hivemind-backend) — Main monorepo
- [hivemind-common](https://github.com/AhmedNijim92/hivemind-common) — Shared DTOs
- [hivemind-frontend](https://github.com/AhmedNijim92/hivemind-frontend) — Next.js frontend
