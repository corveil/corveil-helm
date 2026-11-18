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
Labels shared by every Corveil pod (api, workers, system jobs), used by the NetworkPolicy.
*/}}
{{- define "corveil.partOfLabels" -}}
app.kubernetes.io/part-of: corveil
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Workers selector labels. A distinct app.kubernetes.io/name keeps workers pods out of the
api Service and Deployment selectors, which are unchanged from chart 1.x.
*/}}
{{- define "corveil.workers.selectorLabels" -}}
app.kubernetes.io/name: {{ printf "%s-workers" (include "corveil.name" .) | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "corveil.workers.fullname" -}}
{{- printf "%s-workers" (include "corveil.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Image reference.
*/}}
{{- define "corveil.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- end }}

{{/*
Name of the license Secret.
*/}}
{{- define "corveil.licenseSecretName" -}}
{{- if .Values.license.existingSecret }}
{{- .Values.license.existingSecret }}
{{- else }}
{{- printf "%s-license" .Release.Name }}
{{- end }}
{{- end }}

{{/*
envFrom shared by every Corveil container.
*/}}
{{- define "corveil.envFrom" -}}
- configMapRef:
    name: {{ .Release.Name }}-env
- secretRef:
    name: {{ include "corveil.secretName" . }}
{{- end }}

{{/*
Volumes shared by every Corveil pod that verifies the license or reads the filesystem sensor.
Renders nothing when neither is enabled.
*/}}
{{- define "corveil.volumes" -}}
{{- if .Values.license.enabled }}
- name: license
  secret:
    secretName: {{ include "corveil.licenseSecretName" . }}
    items:
      - key: {{ .Values.license.keySecretKey }}
        path: {{ .Values.license.keySecretKey }}
      - key: {{ .Values.license.publicKeySecretKey }}
        path: {{ .Values.license.publicKeySecretKey }}
{{- end }}
{{- if .Values.knowledge.sensors.filesystem.enabled }}
- name: sensor-files
  {{- toYaml .Values.knowledge.sensors.filesystem.volume | nindent 2 }}
{{- end }}
{{- with .Values.extraVolumes }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "corveil.volumeMounts" -}}
{{- if .Values.license.enabled }}
- name: license
  mountPath: {{ .Values.license.mountPath }}
  readOnly: true
{{- end }}
{{- if .Values.knowledge.sensors.filesystem.enabled }}
- name: sensor-files
  mountPath: {{ .Values.knowledge.sensors.filesystem.mountPath }}
  readOnly: true
{{- end }}
{{- with .Values.extraVolumeMounts }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Init container that waits for the bundled PostgreSQL.
*/}}
{{- define "corveil.waitForDb" -}}
{{- if .Values.postgresql.enabled }}
initContainers:
  - name: wait-for-db
    image: busybox:1.37
    command:
      - sh
      - -c
      - |
        echo "Waiting for {{ .Release.Name }}-postgresql:5432..."
        for i in $(seq 1 60); do
          if nc -z {{ .Release.Name }}-postgresql 5432; then
            echo "Database is ready"
            exit 0
          fi
          echo "Attempt $i/60, waiting 2s..."
          sleep 2
        done
        echo "Database not ready after 120s"
        exit 1
    securityContext:
      {{- toYaml .Values.securityContext | nindent 6 }}
{{- end }}
{{- end }}

{{/*
Validation and migration guards, included from an always-rendered template so a bad or
stale values file fails at template time with an actionable message instead of producing a
pod that crash-loops (or silently ignores a setting). See CHANGELOG.md.
*/}}
{{- define "corveil.migrationGuards" -}}
{{- /* chart 1.0.0: Citadel -> Corveil */}}
{{- if .Values.citadel }}
{{- fail "chart 1.0.0: the `citadel:` values block was renamed to `corveil:` — migrate your overrides (e.g. citadel.secretKey → corveil.secretKey). See CHANGELOG.md [1.0.0] Upgrade." }}
{{- end }}
{{- if and .Values.istio .Values.istio.citadel }}
{{- fail "chart 1.0.0: the `istio.citadel:` values block was renamed to `istio.corveil:` — migrate your gateways/hosts overrides. See CHANGELOG.md [1.0.0] Upgrade." }}
{{- end }}
{{- if .Values.socketzero }}
{{- fail "chart 1.0.0: the `socketzero:` values block was removed (SocketZero JWT auth is no longer bundled) — remove it from your overrides. See CHANGELOG.md [1.0.0] Removed." }}
{{- end }}
{{- /* chart 2.0.0: Corveil v0.5.x */}}
{{- if hasKey .Values "replicaCount" }}
{{- fail "chart 2.0.0: `replicaCount` moved to `api.replicaCount`. See CHANGELOG.md [2.0.0] Upgrade." }}
{{- end }}
{{- if hasKey .Values "resources" }}
{{- fail "chart 2.0.0: `resources` moved to `api.resources` (workers and system jobs have their own). See CHANGELOG.md [2.0.0] Upgrade." }}
{{- end }}
{{- if hasKey .Values "modelsConfig" }}
{{- fail "chart 2.0.0: `modelsConfig` was removed. Corveil v0.5 no longer reads a models.yaml: models come from the built-in catalog and catalog_sync, and org admins enable them under Governance → Models. Remove it from your overrides." }}
{{- end }}
{{- if or (hasKey .Values "redis") (hasKey .Values "externalRedis") }}
{{- fail "chart 2.0.0: the `redis` subchart and `externalRedis` were removed. Corveil v0.5 does not use Redis (it never read REDIS_URL). Remove both from your overrides." }}
{{- end }}
{{- if hasKey .Values "logging" }}
{{- fail "chart 2.0.0: `logging.requestBody` / `logging.responseBody` were removed. Corveil v0.5 does not read LOG_REQUEST_BODY / LOG_RESPONSE_BODY; body capture is bounded by REQUEST_LOG_BODY_MAX_KB (set it through extraEnv). Remove `logging` from your overrides." }}
{{- end }}
{{- if hasKey .Values.corveil "okta" }}
{{- fail "chart 2.0.0: `corveil.okta` was removed. Corveil v0.5 has no Okta sign-in (OKTA_* is not read). See docs/CONFIGURATION.md (Authentication). Remove it from your overrides." }}
{{- end }}
{{- if hasKey .Values.corveil "devLoginEnabled" }}
{{- fail "chart 2.0.0: `corveil.devLoginEnabled` was renamed to `corveil.devAuth` (DEV_AUTH). It requires corveil.environment=development." }}
{{- end }}
{{- if and .Values.corveil.guardrails (hasKey .Values.corveil.guardrails "openaiModeration") }}
{{- fail "chart 2.0.0: `corveil.guardrails.openaiModeration` was removed; Corveil v0.5 does not read GUARDRAIL_OPENAI_MODERATION. Configure guardrails per org in the UI." }}
{{- end }}
{{- /* Settings the app itself refuses at boot */}}
{{- $dev := eq (toString .Values.corveil.environment) "development" }}
{{- if and .Values.corveil.devAuth (not $dev) }}
{{- fail (printf "corveil.devAuth=true requires corveil.environment=development (got %q). DEV_AUTH is an evaluation-only login and Corveil refuses to boot with it anywhere else." (toString .Values.corveil.environment)) }}
{{- end }}
{{- if and (not $dev) (not .Values.existingSecret) }}
{{- if not .Values.corveil.uiSessionSecret }}
{{- fail (printf "corveil.uiSessionSecret is required when corveil.environment=%s (Corveil refuses the default). Set it (e.g. `openssl rand -hex 32`) or provide existingSecret." (toString .Values.corveil.environment)) }}
{{- end }}
{{- if and (not .Values.postgresql.enabled) (not .Values.externalDatabase.systemUrl) }}
{{- fail (printf "externalDatabase.systemUrl (DATABASE_URL_SYSTEM, the BYPASSRLS corveil_system role) is required when corveil.environment=%s and postgresql.enabled=false: Corveil refuses to boot without it. Create the role per docs/CONFIGURATION.md (Database roles), or provide existingSecret with DATABASE_URL_SYSTEM." (toString .Values.corveil.environment)) }}
{{- end }}
{{- end }}
{{- if and .Values.postgresql.enabled .Values.externalDatabase.url }}
{{- fail "set either postgresql.enabled=true or externalDatabase.url, not both." }}
{{- end }}
{{- if and (not .Values.postgresql.enabled) (not .Values.externalDatabase.url) (not .Values.existingSecret) }}
{{- fail "no database configured: set externalDatabase.url (with postgresql.enabled=false), keep postgresql.enabled=true for an evaluation, or provide existingSecret with DATABASE_URL." }}
{{- end }}
{{- if .Values.license.enabled }}
{{- if not .Values.license.org }}
{{- fail "license.org (CORVEIL_LICENSE_ORG, the organization name the license was issued to) is required when license.enabled=true." }}
{{- end }}
{{- if not .Values.license.orgId }}
{{- fail "license.orgId (CORVEIL_LICENSE_ORG_ID, the licensed organization's UUID) is required when license.enabled=true." }}
{{- end }}
{{- if and (not .Values.license.existingSecret) (or (not .Values.license.key) (not .Values.license.publicKey)) }}
{{- fail "license.enabled=true needs license.key and license.publicKey, or license.existingSecret." }}
{{- end }}
{{- end }}
{{- if and .Values.knowledge.sensors.filesystem.enabled (not .Values.knowledge.sensors.filesystem.volume) }}
{{- fail "knowledge.sensors.filesystem.enabled=true needs knowledge.sensors.filesystem.volume (e.g. persistentVolumeClaim: {claimName: corveil-sensors})." }}
{{- end }}
{{- end }}
