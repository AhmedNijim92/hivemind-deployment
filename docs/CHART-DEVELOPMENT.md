# HiveMind — Helm Chart Development Guide

## Chart Template Patterns

### Helper Functions (`_helpers.tpl`)

All backend services use a standardized helper library:

```yaml
{{- define "service.name" -}}           # Chart.Name (e.g., "auth-service")
{{- define "service.fullname" -}}       # ReleaseName-ChartName (truncated to 63 chars)
{{- define "service.labels" -}}         # Full Kubernetes recommended label set
{{- define "service.selectorLabels" -}} # Minimal selector labels (immutable)
{{- define "service.serviceAccountName" -}} # ServiceAccount name resolution
```

### Label Strategy

Every resource includes Kubernetes recommended labels:

```yaml
app: auth-service                          # Legacy app label (for selectors)
app.kubernetes.io/name: auth-service       # Application name
app.kubernetes.io/instance: release-name   # Helm release instance
app.kubernetes.io/version: "1.0.0"         # App version from Chart.yaml
app.kubernetes.io/managed-by: Helm         # Management tool
app.kubernetes.io/component: backend       # Role in architecture
app.kubernetes.io/part-of: hivemind        # Parent application
```

---

## Template Catalog

### deployment.yaml

Key features:
- **RollingUpdate** with `maxSurge: 1, maxUnavailable: 0` (zero downtime)
- **Config checksum annotation** — pods restart when secrets change
- **Pod security context** — runAsNonRoot, drop ALL capabilities
- **Topology spread** — distributes across AZs
- **Three-probe pattern** — startup → liveness → readiness
- **Generic secrets** — iterates `.Values.secrets` map (no hardcoded keys)

### networkpolicy.yaml

Two variants:
1. **Backend services** — ingress only from `app: api-gateway`
2. **API gateway** — ingress from any source (internet-facing)

Both allow DNS egress and pod-to-pod egress within namespace.

### pdb.yaml

Supports both strategies:
- `minAvailable` (preferred): ensures N pods always up
- `maxUnavailable`: allows N pods to be down simultaneously

### serviceaccount.yaml

- `automountServiceAccountToken: false` by default (security)
- Supports annotations for IRSA (AWS IAM roles)
- Conditional creation via `serviceAccount.create`

### secret.yaml

Generic template that iterates over the `secrets` map in values:
```yaml
{{- range $key, $value := .Values.secrets }}
{{ $key }}: {{ $value | quote }}
{{- end }}
```

This means you never need to modify the template — just add/remove keys in `values.yaml`.

### ingress.yaml (gateway + frontend only)

Supports:
- Multiple hosts with multiple paths
- TLS with automatic cert-manager provisioning
- Custom annotations (proxy settings, rate limiting)
- IngressClass selection

---

## Adding New Values

When adding a new configuration option:

1. Add default in `charts/{service}/values.yaml`
2. Add environment overrides in `environments/{env}/{service}-values.yaml`
3. Reference in templates using `{{ .Values.newField }}`
4. Use `{{- if .Values.newField }}` for optional features

### Conditional Features Pattern

```yaml
# values.yaml
featureName:
  enabled: false

# template
{{- if .Values.featureName.enabled }}
apiVersion: ...
kind: ...
{{- end }}
```

---

## Testing Charts

### Lint

```bash
helm lint charts/auth-service/

# Or all charts
make validate ENV=dev
```

### Template Rendering (Dry Run)

```bash
helm template auth-service charts/auth-service/ \
  -f environments/dev/auth-service-values.yaml \
  --namespace hivemind
```

### Diff Before Deploy

```bash
make diff ENV=prod
```

This shows exactly what would change without applying.

---

## Versioning Strategy

### Chart.yaml

```yaml
apiVersion: v2
name: auth-service
version: 1.0.0        # Chart version (bump on template changes)
appVersion: "1.0.0"   # Application version (bump on code changes)
```

- `version`: Increment when templates/values change
- `appVersion`: Tracks the Docker image version

### Upgrade Workflow

1. Update `appVersion` in Chart.yaml
2. Update `image.tag` in environment values
3. Run `make diff ENV=prod` to preview
4. Run `make deploy ENV=prod` to apply
5. Verify with `make status ENV=prod`
6. If issues: `make rollback SERVICE=auth-service ENV=prod`
