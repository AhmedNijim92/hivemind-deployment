{{- define "service.name" -}}
{{- .Chart.Name }}
{{- end }}

{{- define "service.labels" -}}
app: {{ include "service.name" . }}
version: {{ .Chart.AppVersion }}
{{- end }}
