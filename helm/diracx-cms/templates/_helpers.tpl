{{/*
Expand the name of the release (all objects use this as prefix).
*/}}
{{- define "diracx-cms.name" -}}
{{- .Values.global.releaseName | default .Release.Name }}
{{- end }}

{{/*
MySQL service hostname.
Uses bundled service when mysql.enabled, otherwise external host:port.
*/}}
{{- define "diracx-cms.mysqlHost" -}}
{{- if .Values.mysql.enabled -}}
{{ include "diracx-cms.name" . }}-mysql
{{- else -}}
{{ required "external.mysql.host is required when mysql.enabled=false" .Values.external.mysql.host }}:{{ .Values.external.mysql.port | default 3306 }}
{{- end }}
{{- end }}

{{/*
OpenSearch service hostname.
*/}}
{{- define "diracx-cms.osHost" -}}
{{- if .Values.opensearch.enabled -}}
opensearch-cluster-master:9200
{{- else -}}
{{ required "external.opensearch.host is required when opensearch.enabled=false" .Values.external.opensearch.host }}:{{ .Values.external.opensearch.port | default 9200 }}
{{- end }}
{{- end }}

{{/*
MinIO endpoint URL.
*/}}
{{- define "diracx-cms.minioEndpoint" -}}
{{- if .Values.minio.enabled -}}
http://{{ .Values.global.hostname }}:{{ .Values.minio.nodePort }}
{{- else -}}
{{ required "external.minio.endpointUrl is required when minio.enabled=false" .Values.external.minio.endpointUrl }}
{{- end }}
{{- end }}

{{/*
DiracX public base URL (used for auth redirects and token issuer).
*/}}
{{- define "diracx-cms.publicUrl" -}}
https://{{ .Values.global.hostname }}:8000
{{- end }}

{{/*
Dex issuer URL.
*/}}
{{- define "diracx-cms.dexIssuer" -}}
http://{{ .Values.global.hostname }}:{{ .Values.dex.nodePort }}
{{- end }}

{{/*
Common labels applied to every object.
*/}}
{{- define "diracx-cms.labels" -}}
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/instance: {{ include "diracx-cms.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/*
Job spec boilerplate.
*/}}
{{- define "diracx-cms.jobSpec" -}}
activeDeadlineSeconds: {{ .Values.jobs.activeDeadlineSeconds }}
backoffLimit: {{ .Values.jobs.backoffLimit }}
completions: 1
parallelism: 1
ttlSecondsAfterFinished: {{ .Values.jobs.ttlSecondsAfterFinished }}
{{- end }}
