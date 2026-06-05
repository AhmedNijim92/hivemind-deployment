# HiveMind Deployment — Operations Guide

> Production-grade Kubernetes deployment for the HiveMind microservices platform

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Directory Structure](#directory-structure)
3. [Prerequisites](#prerequisites)
4. [Deployment Order](#deployment-order)
5. [Environment Configuration](#environment-configuration)
6. [Secrets Management](#secrets-management)
7. [Helm Charts Reference](#helm-charts-reference)
8. [Networking & Security](#networking--security)
9. [Observability](#observability)
10. [Operations Runbook](#operations-runbook)
11. [Disaster Recovery](#disaster-recovery)

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────────────────────────┐
│                         KUBERNETES CLUSTER (EKS)                           │
│                                                                            │
│  ┌──────────────────── Namespace: hivemind ──────────────────────────┐    │
│  │                                                                    │    │
│  │  ┌─────────────┐     ┌─────────────────────────────────────────┐ │    │
│  │  │   Ingress   │────▶│         API Gateway (×2-10)             │ │    │
│  │  │  (nginx +   │     │  JWT validation, rate limiting, CORS    │ │    │
│  │  │  cert-mgr)  │     └────────────────┬────────────────────────┘ │    │
│  │  └─────────────┘                      │                          │    │
│  │                    ┌──────────────────┼──────────────────────┐   │    │
│  │                    ▼                  ▼                      ▼   │    │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐          │    │
│  │  │  Auth    │ │  User    │ │  Group   │ │  Post    │  ...     │    │
│  │  │ Service  │ │ Service  │ │ Service  │ │ Service  │          │    │
│  │  │  (×2-10) │ │  (×2-10) │ │  (×2-8)  │ │  (×2-10) │          │    │
│  │  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘          │    │
│  │       │             │            │            │                 │    │
│  │  ┌────▼─────────────▼────────────▼────────────▼─────────────┐  │    │
│  │  │              DATA LAYER                                   │  │    │
│  │  │  Cassandra (×1-3)  │  Redis (×1)  │  Kafka (×1-3)       │  │    │
│  │  │  MongoDB (×1-3)    │  PostgreSQL   │                      │  │    │
│  │  └──────────────────────────────────────────────────────────┘  │    │
│  │                                                                    │    │
│  │  ┌─────────────── OBSERVABILITY ──────────────────────────────┐  │    │
│  │  │  Prometheus  │  Grafana  │  Zipkin  │  Alert Rules         │  │    │
│  │  └────────────────────────────────────────────────────────────┘  │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                                                                            │
│  ResourceQuota: 20 CPU / 40Gi RAM │ LimitRange enforced per container     │
└────────────────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
hivemind-deployment/
├── helmfile.yaml                    # Root orchestrator
├── helmfile.d/                      # Layered deployment order
│   ├── 00-namespace.yaml           # Namespace + ResourceQuota + LimitRange
│   ├── 00-infrastructure.yaml      # Cassandra, Kafka, Redis, MongoDB, PostgreSQL
│   ├── 01-platform.yaml            # Eureka Server, Config Server
│   ├── 02-services.yaml            # All domain services + gateway + frontend
│   └── 03-monitoring.yaml          # Prometheus, Grafana, Zipkin, Alert Rules
├── charts/                          # 14 Helm charts
│   ├── namespace-setup/            # Namespace governance (quota, limits)
│   ├── prometheus-rules/           # PrometheusRule CRD alerting
│   ├── eureka-server/
│   ├── config-server/
│   ├── api-gateway/                # Includes Ingress template
│   ├── auth-service/
│   ├── user-service/
│   ├── group-service/
│   ├── post-service/
│   ├── meeting-service/
│   ├── notification-service/
│   ├── media-service/
│   ├── frontend/                   # Includes Ingress template
│   └── zipkin/
├── environments/
│   ├── dev/                        # 1 replica, minimal resources
│   ├── staging/                    # 2 replicas, production-like
│   └── prod/                       # 3-5 replicas, full resources
├── scripts/
│   ├── deploy.sh
│   ├── rollback.sh
│   └── diff.sh
├── .sops.yaml                      # SOPS encryption rules (age key)
├── Makefile                         # CLI shortcuts
└── docs/                            # This documentation
```

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| kubectl | 1.28+ | Cluster interaction |
| Helm | 3.14+ | Chart installation |
| Helmfile | 0.162+ | Multi-chart orchestration |
| SOPS | 3.8+ | Secret encryption |
| age | 1.1+ | Encryption key for SOPS |
| AWS CLI | 2.x | EKS authentication |

### Cluster Requirements

- Kubernetes 1.28+
- Ingress NGINX controller installed
- cert-manager installed (for TLS)
- metrics-server installed (for HPA)
- At least 3 nodes across 2+ AZs (production)

---

## Deployment Order

The helmfile orchestrates deployment in strict order:

```
1. 00-namespace.yaml     → Namespace, ResourceQuota, LimitRange
2. 00-infrastructure.yaml → Cassandra, Kafka, Redis, MongoDB, PostgreSQL
3. 01-platform.yaml      → Eureka Server, Config Server
4. 02-services.yaml      → Auth → User/Group/Post/Meeting → Notification/Media → Gateway → Frontend
5. 03-monitoring.yaml    → Prometheus → Grafana, Zipkin, Alert Rules
```

Each layer waits for the previous to be healthy (`helmDefaults.wait: true`).

Within `02-services.yaml`, the `needs:` field enforces dependency order:
- auth-service depends on: cassandra, kafka, eureka-server
- user/group/post services depend on: cassandra, kafka, redis, auth-service
- notification-service depends on: kafka, mongodb
- media-service depends on: postgresql
- api-gateway depends on: all domain services
- frontend depends on: api-gateway

---

## Environment Configuration

### Dev (`environments/dev/values.yaml`)

| Setting | Value |
|---------|-------|
| Domain | dev.hivemind.local |
| Image Tag | latest |
| Replicas | 1 per service |
| Infra replicas | 1 (single-node) |
| Storage class | standard |

### Staging (`environments/staging/values.yaml`)

| Setting | Value |
|---------|-------|
| Domain | staging.hivemind.io |
| Image Tag | latest (from develop branch) |
| Replicas | 2 per service |
| Infra replicas | 1 |
| Storage class | standard |

### Prod (`environments/prod/values.yaml`)

| Setting | Value |
|---------|-------|
| Domain | api.hivemind.com |
| Image Tag | v1.0.0 (pinned) |
| Replicas | 3-5 per service |
| Infra replicas | 3 (HA) |
| Storage class | fast-ssd |

---

## Secrets Management

### SOPS + age Encryption

Secrets are encrypted at rest using [SOPS](https://github.com/getsops/sops) with [age](https://github.com/FiloSottile/age) keys.

```bash
# Generate a new age key (one-time setup)
age-keygen -o keys.txt

# Encrypt a values file
sops --encrypt environments/prod/auth-service-values.yaml > environments/prod/auth-service-values.enc.yaml

# Decrypt for editing
sops environments/prod/auth-service-values.enc.yaml

# Helmfile automatically decrypts via helm-secrets plugin
```

### Secret Values Per Service

| Service | Secrets |
|---------|---------|
| auth-service | JWT_SECRET, TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_PHONE_NUMBER |
| api-gateway | JWT_SECRET (must match auth-service) |
| media-service | DB_PASSWORD, AWS_ACCESS_KEY, AWS_SECRET_KEY |

### Important

- Never commit plaintext secrets to Git
- Rotate JWT_SECRET across auth-service AND api-gateway simultaneously
- Use Kubernetes External Secrets Operator for production (AWS Secrets Manager integration)

---

## Helm Charts Reference

### Template Structure (Backend Services)

Each backend service chart contains:

| Template | Purpose |
|----------|---------|
| `_helpers.tpl` | Standardized labels, selectors, service account name |
| `deployment.yaml` | Pod spec with security, probes, topology spread |
| `service.yaml` | ClusterIP service |
| `hpa.yaml` | Horizontal Pod Autoscaler (CPU-based) |
| `pdb.yaml` | PodDisruptionBudget |
| `networkpolicy.yaml` | Ingress/egress rules |
| `serviceaccount.yaml` | Dedicated service account |
| `secret.yaml` | Kubernetes Secret from values |
| `ingress.yaml` | (gateway + frontend only) |

### Values Schema

```yaml
replicaCount: 2                    # Base replica count
revisionHistoryLimit: 5            # ReplicaSet history for rollback
terminationGracePeriodSeconds: 30  # Graceful shutdown window

image:
  repository: hivemind/auth-service
  tag: "1.0.0"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP                  # Always ClusterIP (Ingress handles external)
  port: 8081

resources:
  requests: { memory: 512Mi, cpu: 250m }
  limits: { memory: 1Gi, cpu: 500m }

env: {}                            # Plain environment variables
secrets: {}                        # Sensitive values (mounted from Secret)

serviceAccount:
  create: true
  annotations: {}                  # e.g., IRSA for AWS
  automountToken: false

hpa:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

pdb:
  enabled: true
  minAvailable: 1                  # At least 1 pod always available

networkPolicy:
  enabled: true                    # Restrict ingress to gateway only

topologySpreadConstraints: [...]   # Multi-AZ distribution
```

---

## Networking & Security

### Network Policies

Every backend service has a NetworkPolicy that:
- **Allows ingress** only from `api-gateway` pods on the service port
- **Allows egress** to DNS (port 53 TCP/UDP) and any pod in the namespace
- **Denies** all other traffic by default

The api-gateway allows ingress from any source (it's the public entry point).

### Pod Security

All pods run with:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
containers:
  - securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: [ALL]
```

### Ingress (TLS)

The api-gateway Ingress uses:
- `nginx` ingress class
- cert-manager for automatic Let's Encrypt TLS
- Annotations for proxy timeouts and body size (50MB for media uploads)

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
  tls:
    - secretName: hivemind-api-tls
      hosts: [api.hivemind.example.com]
```

---

## Observability

### Prometheus Metrics

All Spring Boot services expose metrics via `/actuator/prometheus` (when actuator is configured). Prometheus scrapes these automatically.

### Alert Rules

Deployed via `prometheus-rules` chart (PrometheusRule CRD):

| Alert | Trigger | Severity |
|-------|---------|----------|
| PodCrashLooping | Restart rate > 0 for 5m | Critical |
| PodNotReady | Not ready for 5m | Warning |
| HighPodMemoryUsage | > 85% of limit for 5m | Warning |
| HighPodCPUUsage | > 80% of limit for 10m | Warning |
| ServiceDown | Target unreachable for 2m | Critical |
| HighErrorRate | > 5% 5xx responses for 5m | Critical |
| HighResponseLatency | P95 > 2s for 5m | Warning |
| KafkaConsumerLag | Lag > 1000 for 10m | Warning |
| CassandraDown | Unreachable for 1m | Critical |
| RedisDown | Unreachable for 1m | Critical |
| PVCAlmostFull | > 85% capacity for 5m | Warning |

### Distributed Tracing

Zipkin collects traces from all services. Access via:
```
kubectl port-forward svc/zipkin 9411:9411 -n hivemind
```

### Grafana Dashboards

Access via:
```
kubectl port-forward svc/grafana 3000:80 -n hivemind
```

---

## Operations Runbook

### Deploy All Services

```bash
# Deploy to dev
make deploy ENV=dev

# Deploy to production
make deploy ENV=prod

# Preview changes before deploying
make diff ENV=prod
```

### Deploy Single Service

```bash
# Deploy only auth-service to production
make deploy ENV=prod SERVICE=auth-service
```

### Rollback

```bash
# Rollback auth-service to previous revision
make rollback SERVICE=auth-service ENV=prod

# Rollback to specific revision
helm rollback auth-service 3 -n hivemind
```

### Check Status

```bash
# All services
make status ENV=prod

# Specific service pods
kubectl get pods -n hivemind -l app=auth-service

# View logs
kubectl logs -f deployment/auth-service -n hivemind

# View events
kubectl get events -n hivemind --sort-by=.lastTimestamp
```

### Scale Manually

```bash
# Scale auth-service to 5 replicas
kubectl scale deployment auth-service --replicas=5 -n hivemind

# HPA will take over again based on CPU usage
```

### Access Services (Port Forward)

```bash
kubectl port-forward svc/api-gateway 8080:8080 -n hivemind
kubectl port-forward svc/eureka-server 8761:8761 -n hivemind
kubectl port-forward svc/grafana 3000:80 -n hivemind
kubectl port-forward svc/zipkin 9411:9411 -n hivemind
```

### View Resource Usage

```bash
# Pod resource consumption
kubectl top pods -n hivemind

# Node resource consumption
kubectl top nodes

# Check ResourceQuota usage
kubectl describe resourcequota hivemind-quota -n hivemind
```

---

## Disaster Recovery

### Database Backups

| Database | Strategy | Frequency |
|----------|----------|-----------|
| Cassandra | Snapshot to S3 via `nodetool snapshot` | Daily |
| MongoDB | `mongodump` to S3 | Daily |
| PostgreSQL | `pg_dump` via CronJob | Daily + hourly WAL |
| Redis | RDB snapshots | Hourly |

### Full Cluster Recovery

```bash
# 1. Ensure kubectl points to new cluster
aws eks update-kubeconfig --name hivemind-prod --region us-east-1

# 2. Deploy infrastructure first (databases will use PVCs)
helmfile -e prod -f helmfile.d/00-namespace.yaml sync
helmfile -e prod -f helmfile.d/00-infrastructure.yaml sync

# 3. Restore data from backups
# (restore scripts per database)

# 4. Deploy platform and services
helmfile -e prod sync
```

### Service-Level Recovery

If a single service is failing:

```bash
# 1. Check pod status
kubectl describe pod <pod-name> -n hivemind

# 2. Check logs
kubectl logs <pod-name> -n hivemind --previous

# 3. Rollback to last known good
helm rollback <service-name> 0 -n hivemind

# 4. If rollback doesn't help, redeploy
helmfile -e prod -l app=<service-name> apply
```

---

## Configuration Reference

### Helmfile Defaults

```yaml
helmDefaults:
  wait: true       # Wait for resources to be ready
  timeout: 600     # 10 minute timeout per release
  atomic: true     # Auto-rollback on failure
  force: false     # Don't force resource updates
```

### Resource Quotas (Namespace Level)

| Resource | Limit |
|----------|-------|
| requests.cpu | 20 cores |
| requests.memory | 40Gi |
| limits.cpu | 40 cores |
| limits.memory | 80Gi |
| pods | 100 |
| services | 30 |
| secrets | 50 |
| configmaps | 50 |

### Container Limit Ranges

| Setting | Value |
|---------|-------|
| Default CPU | 500m |
| Default Memory | 512Mi |
| Default Request CPU | 100m |
| Default Request Memory | 128Mi |
| Max CPU | 4 cores |
| Max Memory | 8Gi |
| Min CPU | 50m |
| Min Memory | 64Mi |

---

## Upgrade Procedures

### Rolling Update Strategy

All services use:
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1        # Create 1 new pod before killing old
    maxUnavailable: 0  # Never reduce below desired count
```

This ensures zero-downtime deployments.

### Startup Probe (Java Services)

Java/Spring services have slow startup (JVM + Spring context). The startup probe allows up to 230 seconds:
```yaml
startupProbe:
  initialDelaySeconds: 30    # Wait 30s for JVM
  periodSeconds: 10          # Check every 10s
  failureThreshold: 20       # Allow 20 failures = 230s total
```

Liveness and readiness probes only activate after the startup probe succeeds.

### Image Tag Strategy

| Environment | Tag Strategy |
|-------------|-------------|
| Dev | `latest` (auto-deploy on push) |
| Staging | `latest` or branch SHA |
| Prod | Pinned semantic version (`v1.2.3`) |

---

## Adding a New Service

1. Copy an existing chart (e.g., `charts/user-service/`)
2. Update `Chart.yaml` (name, description)
3. Update `values.yaml` (port, env vars, secrets)
4. Add entry to `helmfile.d/02-services.yaml` with `needs:`
5. Create environment values files: `environments/{env}/{service}-values.yaml`
6. Add route to api-gateway's `application.yml`
7. Deploy: `make deploy ENV=dev`
