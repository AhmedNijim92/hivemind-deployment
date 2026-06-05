# HiveMind Deployment — Security Architecture

## Defense-in-Depth Model

```
Layer 1: Ingress (TLS termination, rate limiting)
Layer 2: NetworkPolicy (pod-to-pod isolation)
Layer 3: Pod Security (non-root, drop capabilities)
Layer 4: Service Accounts (minimal RBAC)
Layer 5: Secrets (SOPS encryption at rest)
Layer 6: Application (JWT validation, input validation)
```

---

## Network Security

### NetworkPolicy Design

```
                    INTERNET
                        │
                        ▼
              ┌─────────────────┐
              │  Ingress NGINX  │
              └────────┬────────┘
                       │ (any → port 8080)
              ┌────────▼────────┐
              │   API Gateway   │  ← Open ingress (public entry point)
              └────────┬────────┘
                       │ (gateway → service port)
    ┌──────────┬───────┼───────┬──────────┬──────────┐
    ▼          ▼       ▼       ▼          ▼          ▼
┌──────┐  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐  ┌──────┐
│ Auth │  │ User │ │Group │ │ Post │ │Meet  │  │Media │
│      │  │      │ │      │ │      │ │      │  │      │
└──┬───┘  └──┬───┘ └──┬───┘ └──┬───┘ └──┬───┘  └──┬───┘
   │         │        │        │        │         │
   └─────────┴────────┴────────┴────────┴─────────┘
                       │ (pods → infra ports)
              ┌────────▼────────────────────────┐
              │  Cassandra, Kafka, Redis, etc.  │
              └─────────────────────────────────┘
```

### Policy Rules

| Service | Ingress From | Egress To |
|---------|-------------|-----------|
| api-gateway | Any (internet) | All pods in namespace |
| auth-service | api-gateway only | Cassandra, Kafka, DNS |
| user-service | api-gateway only | Cassandra, Redis, Kafka, DNS |
| group-service | api-gateway only | Cassandra, Redis, Kafka, DNS |
| post-service | api-gateway only | Cassandra, Redis, Kafka, DNS |
| meeting-service | api-gateway only | Cassandra, Redis, Kafka, DNS |
| notification-service | api-gateway only | MongoDB, Kafka, DNS |
| media-service | api-gateway only | PostgreSQL, DNS |
| frontend | Any (internet) | api-gateway, DNS |

### Disabling NetworkPolicies (Development)

For local development where a CNI that supports NetworkPolicy isn't available:

```yaml
# In environments/dev/*-values.yaml
networkPolicy:
  enabled: false
```

---

## Pod Security

### Security Context (All Services)

```yaml
spec:
  securityContext:
    runAsNonRoot: true     # Pods cannot run as root
    runAsUser: 1000        # Non-privileged UID
    runAsGroup: 1000       # Non-privileged GID
    fsGroup: 1000          # File system group
  containers:
    - securityContext:
        allowPrivilegeEscalation: false  # Cannot gain more privileges
        readOnlyRootFilesystem: false    # JVM needs /tmp writes
        capabilities:
          drop: [ALL]                    # No Linux capabilities
```

### Why `readOnlyRootFilesystem: false`?

Java applications (Spring Boot) write to:
- `/tmp` for Tomcat work directories
- JVM compiler cache files

If you want `readOnlyRootFilesystem: true`, mount an emptyDir at `/tmp`:
```yaml
volumes:
  - name: tmp
    emptyDir: {}
volumeMounts:
  - name: tmp
    mountPath: /tmp
```

---

## Service Accounts

Each service gets a dedicated ServiceAccount:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: auth-service
automountServiceAccountToken: false  # No token mounted unless needed
```

### IRSA (IAM Roles for Service Accounts)

For media-service which needs S3 access:

```yaml
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/hivemind-media-s3
```

This eliminates the need for AWS access keys in secrets.

---

## Secrets Management

### Current: SOPS + age

```
.sops.yaml defines encryption rules per path:
  - environments/prod/**  → encrypted with age key
  - environments/staging/** → encrypted with age key
```

### Upgrade Path: External Secrets Operator

For production, migrate to ESO + AWS Secrets Manager:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: auth-service-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: auth-service-secrets
  data:
    - secretKey: JWT_SECRET
      remoteRef:
        key: hivemind/prod/auth-service
        property: JWT_SECRET
```

---

## TLS / Certificate Management

### cert-manager ClusterIssuer

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: devops@hivemind.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: nginx
```

### Ingress TLS Config

```yaml
ingress:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  tls:
    - secretName: hivemind-api-tls
      hosts:
        - api.hivemind.com
```

cert-manager automatically provisions and renews certificates.

---

## Supply Chain Security

### Image Scanning

Integrate into CI/CD:
```yaml
- name: Scan Docker image
  run: trivy image hivemind/auth-service:${{ github.sha }} --exit-code 1 --severity HIGH,CRITICAL
```

### Image Pull Policy

| Environment | Policy |
|-------------|--------|
| Dev | `Always` (pull latest) |
| Staging | `IfNotPresent` |
| Prod | `IfNotPresent` (pinned tags) |

### Private Registry

If using a private registry (GHCR, ECR):

```yaml
spec:
  imagePullSecrets:
    - name: ghcr-pull-secret
```

Create the secret:
```bash
kubectl create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=$GITHUB_USER \
  --docker-password=$GITHUB_TOKEN \
  -n hivemind
```

---

## Compliance Checklist

- [x] Pods run as non-root (UID 1000)
- [x] No privilege escalation allowed
- [x] All Linux capabilities dropped
- [x] NetworkPolicies restrict pod-to-pod traffic
- [x] Secrets encrypted at rest (SOPS)
- [x] TLS on all external endpoints (cert-manager)
- [x] Rate limiting on public endpoints
- [x] Security headers on all responses (X-Frame-Options, CSP, etc.)
- [x] Service accounts with minimal permissions
- [x] Resource quotas prevent namespace resource exhaustion
- [ ] Pod Security Standards (PSS) enforcement (future: Restricted profile)
- [ ] Image signing with cosign/sigstore (future)
- [ ] OPA/Kyverno policy enforcement (future)
