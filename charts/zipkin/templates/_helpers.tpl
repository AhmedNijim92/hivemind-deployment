{{- define "zipkin.fullname" -}}
{{- .Release.Name }}-zipkin
{{- end }}

{{- define "zipkin.labels" -}}
app.kubernetes.io/name: zipkin
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "zipkin.selectorLabels" -}}
app.kubernetes.io/name: zipkin
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
