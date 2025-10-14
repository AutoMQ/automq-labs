{{- define "automq-benchmark.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "automq-benchmark.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "automq-benchmark.name" . | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "automq-benchmark.labels" -}}
app.kubernetes.io/name: {{ include "automq-benchmark.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "automq-benchmark.selectorLabels" -}}
app.kubernetes.io/name: {{ include "automq-benchmark.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}