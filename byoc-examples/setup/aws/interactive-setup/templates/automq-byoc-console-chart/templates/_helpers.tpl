{{/*
Expand the name of the chart.
*/}}
{{- define "automq-byoc-console.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "automq-byoc-console.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "automq-byoc-console.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "automq-byoc-console.labels" -}}
helm.sh/chart: {{ include "automq-byoc-console.chart" . }}
{{ include "automq-byoc-console.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "automq-byoc-console.selectorLabels" -}}
app.kubernetes.io/name: {{ include "automq-byoc-console.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Define the image repository
*/}}
{{- define "automq-byoc-console.imageRepository" -}}
{{- .Values.image.repository }}
{{- end }}

{{/*
Define the image tag
*/}}
{{- define "automq-byoc-console.imageTag" -}}
{{- .Values.image.tag | default (printf "%s-%s" .Chart.AppVersion .Values.cloudProvider) }}
{{- end }}
