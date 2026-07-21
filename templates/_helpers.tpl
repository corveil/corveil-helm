{{/*
Expand the name of the chart.
*/}}
{{- define "corveil.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "corveil.fullname" -}}
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
{{- define "corveil.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "corveil.labels" -}}
helm.sh/chart: {{ include "corveil.chart" . }}
{{ include "corveil.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "corveil.selectorLabels" -}}
app.kubernetes.io/name: {{ include "corveil.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "corveil.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "corveil.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the name of the Secret to use.
If existingSecret is set, use that; otherwise use release-name-secrets.
*/}}
{{- define "corveil.secretName" -}}
{{- if .Values.existingSecret }}
{{- .Values.existingSecret }}
{{- else }}
{{- printf "%s-secrets" .Release.Name }}
{{- end }}
{{- end }}

{{/*
Migration guards — fail loudly on values keys removed or renamed in chart 1.0.0
(the Citadel → Corveil rebrand). Included from an always-rendered template so a
stale override file produces a clear error at template time instead of a silently
mis-secreted deploy (an ignored `citadel.secretKey` rendering an empty SECRET_KEY).
See CHANGELOG.md [1.0.0]. Safe to remove after the 1.x line.
*/}}
{{- define "corveil.migrationGuards" -}}
{{- if .Values.citadel }}
{{- fail "chart 1.0.0: the `citadel:` values block was renamed to `corveil:` — migrate your overrides (e.g. citadel.secretKey → corveil.secretKey, citadel.okta.* → corveil.okta.*). See CHANGELOG.md [1.0.0] Upgrade." }}
{{- end }}
{{- if and .Values.istio .Values.istio.citadel }}
{{- fail "chart 1.0.0: the `istio.citadel:` values block was renamed to `istio.corveil:` — migrate your gateways/hosts overrides. See CHANGELOG.md [1.0.0] Upgrade." }}
{{- end }}
{{- if .Values.socketzero }}
{{- fail "chart 1.0.0: the `socketzero:` values block was removed (SocketZero JWT auth is no longer bundled) — remove it from your overrides. See CHANGELOG.md [1.0.0] Removed." }}
{{- end }}
{{- end }}
