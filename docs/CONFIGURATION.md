# Configuration Reference

Reference for the Corveil Helm chart's `values.yaml`, chart 2.x (Corveil v0.5). Each
application setting is rendered as the env var in the last column. The api, workers and
system-job containers share one env ConfigMap (`<release>-env`) and one Secret
(`<release>-secrets`, or `existingSecret`), loaded with `envFrom`.

To set an env var the chart doesn't model, use [`extraEnv`](#escape-hatches). The full list of
settings the binary reads is `go/internal/config/config.go` in `corveil/corveil`.

## Core Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Container image repository (private on GHCR) | `ghcr.io/corveil/corveil` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `image.tag` | Image tag; defaults to the chart `appVersion` | `""` |
| `imagePullSecrets` | Pull secrets, e.g. `[{name: ghcr-pull}]` | `[]` |
| `nameOverride` | `app.kubernetes.io/name` of the api pods. Changing it on an existing release alters the immutable Deployment selector. | `"corveil"` |
| `fullnameOverride` | Base resource name (`corveil`, `corveil-workers`, `corveil-<job>`) | `"corveil"` |
| `domain` | Base domain for Big Bang integration | `"bigbang.dev"` |

## Corveil Application

| Parameter | Description | Default | Env Var |
|-----------|-------------|---------|---------|
| `corveil.environment` | `development` is evaluation mode (allows devAuth, default secrets, system-pool fallback). Use `production` for a real install. | `development` | `ENVIRONMENT` |
| `corveil.devAuth` | Evaluation login at `/auth/dev-login`. Only valid with `environment=development`. | `false` | `DEV_AUTH` |
| `corveil.logLevel` | `DEBUG`, `INFO`, `WARN`, `ERROR` | `INFO` | `LOG_LEVEL` |
| `corveil.secretKey` | Encrypts stored credentials and signs tokens. **Required** unless `existingSecret` is set. Keep it stable across upgrades. | `""` | `SECRET_KEY` |
| `corveil.uiSessionSecret` | Signs UI session cookies. Required outside `development`. | `""` | `UI_SESSION_SECRET` |
| `corveil.uiSessionExpiryHours` | UI session lifetime | `24` | `UI_SESSION_EXPIRY_HOURS` |
| `corveil.uiBaseUrl` | Public origin of the UI, e.g. `https://corveil.example.com` | `""` | `UI_BASE_URL` |
| `corveil.sessionAuthAllowedOrigins` | Origins whose session cookie may call `/v1` (the UI chat). Defaults to `uiBaseUrl`. | `[]` | `SESSION_AUTH_ALLOWED_ORIGINS` |
| `corveil.trustedProxyIps` | IPs/CIDRs of the ingress or load balancer, so per-IP limits read `X-Forwarded-For` | `[]` | `TRUSTED_PROXY_IPS` |
| `corveil.providerCredentialsKmsKeyArn` | AWS KMS key that seals per-org provider credentials. Outside `development`, per-org credentials are off without it. | `""` | `CORVEIL_PROVIDER_CREDS_KMS_KEY_ARN` |
| `corveil.apiKeyPrefix` | Prefix of issued API keys. Keep `sk-citadel`: it is the on-the-wire key format. | `"sk-citadel"` | `API_KEY_PREFIX` |
| `corveil.autoProvisionUsers` | Create users on first sign-in | `true` | `AUTO_PROVISION_USERS` |
| `corveil.guardrails.enabled` | Guardrails engine (rules are configured per org in the UI) | `true` | `GUARDRAILS_ENABLED` |
| `corveil.guardrails.piiFilter` | Built-in PII filter | `false` | `GUARDRAIL_PII_FILTER` |
| `corveil.passthrough.enabled` | Let clients send their own provider credential, with the Corveil key in `x-citadel-api-key` | `true` | `PASSTHROUGH_ENABLED` |
| `corveil.plugins.enabled` | Plugin system | `true` | `PLUGINS_ENABLED` |
| `rateLimiting.defaultRpm` | Default requests per minute per key | `60` | `DEFAULT_RATE_LIMIT_RPM` |
| `rateLimiting.defaultTpm` | Default tokens per minute per key | `100000` | `DEFAULT_RATE_LIMIT_TPM` |

### Authentication

Corveil v0.5 has two UI sign-in paths:

- **Dev login** (`corveil.devAuth=true`), for evaluation only. Corveil refuses to start with
  it outside `development`.
- **WorkOS** (`CORVEIL_WORKOS_*`, set through `extraEnv` / `existingSecret`), a hosted
  identity service. It is the only production sign-in in v0.5.

The Okta OIDC values from chart 1.x were removed: the app dropped Okta and never read them.
API clients authenticate with Corveil API keys (`sk-citadel-…`) in every mode.

## Workloads

### API (`corveil serve`)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `api.replicaCount` | Replicas when autoscaling is off | `1` |
| `api.resources` | Container resources | `250m`/`512Mi` requests, `1`/`1Gi` limits |
| `api.extraEnv` | Env for the api container only | `[]` |
| `api.podAnnotations` | Annotations for api pods | `{}` |

The api runs migrations at startup, under a Postgres advisory lock, so replicas starting
together are safe. A `startupProbe` (up to 10 minutes) covers a long first migration. The
readiness probe is `/health/ready`, which checks the database, schema version and guardrails.

### Workers (`corveil workers`)

| Parameter | Description | Default | Env Var |
|-----------|-------------|---------|---------|
| `workers.enabled` | Deploy the workers | `true` | — |
| `workers.replicaCount` | Keep at 1. Scheduled loops take a database leader lock, so more are safe but add no throughput. | `1` | — |
| `workers.healthPort` | Health endpoint port (`/health`) | `8081` | `WORKERS_HEALTH_PORT` |
| `workers.resources` | Container resources | `100m`/`256Mi` requests, `1`/`1Gi` limits | — |
| `workers.extraEnv` | Env for the workers container only | `[]` | — |
| `workers.podAnnotations` | Annotations for workers pods | `{}` | — |

The workers never migrate. They exit while the schema is behind their build, so they restart
until the api has migrated; the Deployment uses `Recreate`. Their pods carry
`app.kubernetes.io/name: corveil-workers`, which keeps them out of the api Service.

### System jobs (`corveil system-job <name>`)

Each enabled entry under `systemJobs.jobs` becomes a CronJob named `corveil-<job>` (`_` becomes
`-`). The schedules mirror the hosted service and are in the controller's time zone (UTC unless
`systemJobs.timeZone` is set). To run one now:
`kubectl create job --from=cronjob/corveil-catalog-sync catalog-sync-now`.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `systemJobs.enabled` | Create the CronJobs | `true` |
| `systemJobs.timeZone` | CronJob `timeZone`, e.g. `Etc/UTC` | `""` |
| `systemJobs.concurrencyPolicy` | | `Forbid` |
| `systemJobs.startingDeadlineSeconds` | | `600` |
| `systemJobs.successfulJobsHistoryLimit` / `failedJobsHistoryLimit` | | `1` / `3` |
| `systemJobs.backoffLimit` | Retries per run. Each job runs again on its next schedule. | `0` |
| `systemJobs.activeDeadlineSeconds` | Per-run timeout | `3600` |
| `systemJobs.resources` | Container resources | `50m`/`128Mi` requests, `500m`/`512Mi` limits |
| `systemJobs.jobs.<name>.enabled` / `.schedule` | Per-job toggle and cron schedule | see below |

| Job | Default schedule | Enabled | Purpose |
|-----|------------------|---------|---------|
| `audit_retention_purge` | `0 3 * * *` | yes | Delete audit events past retention |
| `hard_delete_archived_orgs` | `45 3 * * *` | yes | Delete archived orgs after their grace period |
| `request_log_retention_purge` | `15 5 * * *` | yes | Delete request logs past retention |
| `client_error_retention_purge` | `0 6 * * *` | yes | Delete UI error reports past retention |
| `jobs_retention_purge` | `15 6 * * *` | yes | Delete finished queue jobs |
| `oauth_client_unconsented_purge` | `0 8 * * *` | yes | Delete OAuth clients that were never consented |
| `catalog_sync` | `30 4 * * *` | yes | Discover models with each org's provider credentials |
| `pricing_sync` | `45 4 * * *` | yes | Price models from the public LiteLLM / OpenRouter price lists |
| `ontology_identity_undermerge_sweep` | `0 7 * * *` | yes | Find duplicate person identities in the graph |
| `ontology_entity_degree_recount` | `30 8 * * *` | yes | Repair graph degree counters |
| `crow_session_derive` | `*/5 * * * *` | yes | Turn uploaded Crow session logs into graph entities |
| `gateway_session_derive` | `*/5 * * * *` | yes | Turn gateway traffic into agent sessions |
| `attention_detectors` | `*/15 * * * *` | yes | Evaluate attention / alert detectors |
| `worker_run_abandon_sweep` | `*/15 * * * *` | yes | Fail worker runs whose runner disappeared |
| `worker_run_input_expiry` | `15 8 * * *` | yes | Expire stored worker-run inputs |
| `worker_run_queue_expiry` | `45 8 * * *` | yes | Expire worker runs queued too long |
| `worker_artifact_retention_purge` | `30 5 * * *` | no | Needs artifact object storage |
| `crow_session_artifact_retention_purge` | `45 5 * * *` | no | Needs artifact object storage |
| `dashboard_artifact_retention_purge` | `45 6 * * *` | no | Needs artifact object storage |
| `worker_run_payload_retention_purge` | `30 6 * * *` | no | Needs artifact object storage |
| `worker_run_payload_offload` | `20 * * * *` | no | Needs artifact object storage |

The disabled group sweeps objects in the artifact bucket (`CORVEIL_WORKER_ARTIFACT_S3_BUCKET`
and related settings). Enable it once you configure that bucket through `extraEnv`: without
it, the artifact purges refuse to run. Billing, trial and seat jobs from the hosted service
(Stripe, usage units, Cursor and provider admin reconciliation) are not included.

Every job opens the `DATABASE_URL_SYSTEM` (BYPASSRLS) pool. In `development` without one it
falls back to `DATABASE_URL`.

## Database

Corveil needs PostgreSQL 16+ with the `pgvector` and `pgcrypto` extensions.

### Database roles

Corveil uses three roles. Row-level security (RLS) isolates organizations, so the runtime role
must not be the schema owner:

| Role | Attributes | DSN | Used by |
|------|-----------|-----|---------|
| `corveil` (owner; any name) | owns the database and schema, NOBYPASSRLS | `DATABASE_URL_PRIVILEGED` | api migrations |
| `corveil_app` | LOGIN, NOBYPASSRLS, no DDL | `DATABASE_URL` | every request (api, workers) |
| `corveil_system` | LOGIN, **BYPASSRLS**, no DDL | `DATABASE_URL_SYSTEM` | cross-org reads (api, workers, system jobs) |

`corveil_app` and `corveil_system` must have exactly these names: the migrations grant to them
by name. Outside `development`, the api and workers refuse to start without
`DATABASE_URL_SYSTEM`. If `DATABASE_URL_PRIVILEGED` is empty, the api migrates with
`DATABASE_URL`. That only works when `DATABASE_URL` is the owner, which defeats RLS, so set it.

Create the roles as a superuser (or your cloud's admin role) before the first install.
Replace the passwords, and `corveil` if your owner role has another name:

```sql
CREATE EXTENSION IF NOT EXISTS vector;     -- in the corveil database
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE ROLE corveil        LOGIN PASSWORD '…' NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
CREATE ROLE corveil_app    LOGIN PASSWORD '…' NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
CREATE ROLE corveil_system LOGIN PASSWORD '…' NOSUPERUSER BYPASSRLS   NOCREATEDB NOCREATEROLE;
CREATE DATABASE corveil OWNER corveil;
REVOKE ALL ON DATABASE corveil FROM PUBLIC;
GRANT CONNECT ON DATABASE corveil TO corveil_app, corveil_system;

-- connected to the corveil database:
GRANT USAGE ON SCHEMA public TO corveil_app, corveil_system;
-- corveil_app: table grants come from Corveil's migrations; sequences and functions are blanket.
ALTER DEFAULT PRIVILEGES FOR ROLE corveil IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO corveil_app;
ALTER DEFAULT PRIVILEGES FOR ROLE corveil IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO corveil_app;
-- corveil_system: full DML on every table the owner creates.
ALTER DEFAULT PRIVILEGES FOR ROLE corveil IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO corveil_system;
ALTER DEFAULT PRIVILEGES FOR ROLE corveil IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO corveil_system;
```

On managed PostgreSQL, the admin role must be a member of `corveil` to run
`ALTER DEFAULT PRIVILEGES FOR ROLE corveil` (`GRANT corveil TO <admin>`). On PostgreSQL 15+,
`public` belongs to the database owner, so `corveil` can create tables there. The api also
reconciles `corveil_system`'s table grants on every start.

### Bundled PostgreSQL (Bitnami), for evaluation

| Parameter | Description | Default |
|-----------|-------------|---------|
| `postgresql.enabled` | Deploy the bundled PostgreSQL | `true` |
| `postgresql.auth.database` | Database name | `citadel` |
| `postgresql.auth.username` | Schema owner (the api migrates as it) | `citadel` |
| `postgresql.auth.password` | Password for the owner, `corveil_app` and `corveil_system`. Use URL-safe characters. | `citadel` |
| `postgresql.primary.persistence.size` | Volume size | `8Gi` |
| `postgresql.primary.initdb.scriptsSecret` | Init script that creates pgvector and the two Corveil roles | `{{ .Release.Name }}-db-init` |

On an empty volume, the init script (`templates/db-init-secret.yaml`) gives the bundled
database the role layout above. The chart then sets all three DSNs. The init script doesn't run
on an existing volume, such as one created by chart 1.x. The bundled database is a single
instance with no backups.

### External database

| Parameter | Description | Default | Env Var |
|-----------|-------------|---------|---------|
| `externalDatabase.url` | `corveil_app` DSN | `""` | `DATABASE_URL` |
| `externalDatabase.systemUrl` | `corveil_system` DSN. Required outside `development`. | `""` | `DATABASE_URL_SYSTEM` |
| `externalDatabase.privilegedUrl` | Owner DSN, for migrations | `""` | `DATABASE_URL_PRIVILEGED` |

Set `postgresql.enabled=false`. DSNs look like
`postgresql://corveil_app:<password>@db.example.com:5432/corveil?sslmode=require`. Corveil
requires SCRAM authentication by default (`require_auth=scram-sha-256`). If a role still has an
md5 password, reset it with `\password`, or add `require_auth=scram-sha-256,md5` to its DSN.

## Secrets

| Parameter | Description | Default |
|-----------|-------------|---------|
| `existingSecret` | An existing Secret to load instead of creating `<release>-secrets` | `""` |

The Secret is loaded with `envFrom` into every Corveil container, so its keys are env names:

- Required: `DATABASE_URL`, `SECRET_KEY`
- Required outside `development`: `DATABASE_URL_SYSTEM`, `UI_SESSION_SECRET`
- Recommended: `DATABASE_URL_PRIVILEGED`
- Optional: `OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_APPLICATION_CREDENTIALS_JSON`,
  `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `MCP_RUNNER_INTERNAL_SECRET`, and any other
  secret env var (for example `CORVEIL_WORKOS_API_KEY`)

## Offline License

Entitlements for a self-hosted install come from an offline license (Corveil ADR-0018): a
signed key, verified at boot against a public key you supply. The api and workers both verify
it, and refuse to start if it is invalid, expired, issued to another org, or names an org UUID
that doesn't exist. It is re-checked every `revalidateInterval`. A renewed license written to
the Secret is picked up without a restart.

| Parameter | Description | Default | Env Var |
|-----------|-------------|---------|---------|
| `license.enabled` | Turn on offline licensing | `false` | `CORVEIL_LICENSE_OFFLINE_ENABLED` |
| `license.org` | Organization name the license was issued to | `""` | `CORVEIL_LICENSE_ORG` |
| `license.orgId` | UUID of that organization in this install (`corveil whoami` → `org_id`) | `""` | `CORVEIL_LICENSE_ORG_ID` |
| `license.key` | The license key. Ignored with `existingSecret`. | `""` | (file) |
| `license.publicKey` | PEM public key. Ignored with `existingSecret`. | `""` | (file) |
| `license.existingSecret` | Secret holding both, instead of `<release>-license` | `""` | — |
| `license.keySecretKey` / `publicKeySecretKey` | Key names in that Secret | `license.jwt` / `public.pem` | — |
| `license.mountPath` | Where the Secret is mounted | `/etc/corveil/license` | `CORVEIL_LICENSE_KEY_FILE`, `CORVEIL_LICENSE_PUBLIC_KEY_FILE` |
| `license.revalidateInterval` | Re-validation period | `1h` | `CORVEIL_LICENSE_REVALIDATE_INTERVAL` |

> **Known issue (Corveil v0.5.20):** the boot-time check that `license.orgId` exists reads
> `organizations` as `corveil_app`, which RLS blocks with no org selected. With the role layout
> above, a license that is otherwise valid fails with `does not match any organization`. Keep
> `license.enabled=false` until a Corveil release fixes it.

## Knowledge Layer

These run on the workers Deployment.

| Parameter | Description | Default | Env Var |
|-----------|-------------|---------|---------|
| `knowledge.ontology.enabled` | Knowledge graph (ontology) | `true` | `ONTOLOGY_ENABLED` |
| `knowledge.ontology.sensorBridge` | Turn sensor events into graph entities | `false` | `ONTOLOGY_SENSOR_BRIDGE` |
| `knowledge.ontology.synthesis` | Queue knowledge-page synthesis runs (needs a Crow worker runner) | `false` | `ONTOLOGY_SYNTHESIS_ENABLED` |
| `knowledge.sensors.enabled` | Poll the sensors configured in each org | `false` | `SENSORS_ENABLED` |
| `knowledge.sensors.allowPrivateNetworks` | Let sensors reach private addresses. Single-tenant only. | `false` | `CORVEIL_SENSOR_ALLOW_PRIVATE_NETWORKS` |
| `knowledge.sensors.ambientCredentials` | Let S3 / Google sensors with a blank credential use the pod's cloud identity. Single-tenant only. | `false` | `CORVEIL_SENSOR_AMBIENT_CREDENTIALS` |
| `knowledge.sessions.enabled` | Derive agent sessions from gateway traffic | `true` | `SESSIONS_ENABLED` |

Org admins add sensors in the UI (**Corvus → Sensors**), or with `corveil sensors setup`.

### Filesystem sensor

The filesystem sensor reads files from a volume you mount. Each org is confined to
`<mountPath>/<organization_id>/`.

| Parameter | Description | Default | Env Var |
|-----------|-------------|---------|---------|
| `knowledge.sensors.filesystem.enabled` | Mount the volume and set the root | `false` | — |
| `knowledge.sensors.filesystem.mountPath` | Mount path (read-only) on api and workers | `/var/lib/corveil/sensors` | `FILESYSTEM_SENSOR_ROOT` |
| `knowledge.sensors.filesystem.volume` | Volume source | `{}` | — |

```yaml
knowledge:
  sensors:
    enabled: true
    filesystem:
      enabled: true
      volume:
        persistentVolumeClaim:
          claimName: corveil-sensor-files   # ReadOnlyMany or ReadWriteMany: both api and workers mount it
```

## MCP Runner

The stdio MCP runner is a separate service that this chart does not deploy. These values point
the gateway at one you run.

| Parameter | Description | Default | Env Var |
|-----------|-------------|---------|---------|
| `mcpRunner.allowedHosts` | Comma-separated runner host allowlist | `""` | `MCP_RUNNER_ALLOWED_HOSTS` |
| `mcpRunner.internalSecret` | Shared HMAC secret. Must match the runner's. | `""` | `MCP_RUNNER_INTERNAL_SECRET` |

## LLM Providers

These are deployment-wide credentials that every org can use. Org admins can also add their
own in the UI (Governance → AI Gateway); see `corveil.providerCredentialsKmsKeyArn`.

| Parameter | Description | Default | Env Var |
|-----------|-------------|---------|---------|
| `providers.openrouter.apiKey` | OpenRouter API key | `""` | `OPENROUTER_API_KEY` |
| `providers.openrouter.siteUrl` / `appName` | OpenRouter attribution | `""` | `OPENROUTER_SITE_URL` / `OPENROUTER_APP_NAME` |
| `providers.anthropic.apiKey` | Anthropic API key | `""` | `ANTHROPIC_API_KEY` |
| `providers.vertexai.projectId` | GCP project ID | `""` | `GCP_PROJECT_ID` |
| `providers.vertexai.location` | GCP region | `"us-central1"` | `GCP_LOCATION` |
| `providers.vertexai.credentialsJson` | Service account JSON | `""` | `GOOGLE_APPLICATION_CREDENTIALS_JSON` |
| `providers.bedrock.enabled` | Render the Bedrock region settings | `false` | — |
| `providers.bedrock.region` | AWS region | `"us-east-1"` | `AWS_REGION` |
| `providers.bedrock.accessKeyId` / `secretAccessKey` | Static AWS credentials | `""` | `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` |
| `providers.bedrock.useTaskRole` | Use the pod's IAM identity instead | `false` | `AWS_USE_TASK_ROLE` |

Models are not configured in the chart. Corveil ships a curated catalog, discovers each
provider's models (`catalog_sync`), and org admins enable models under Governance → AI Gateway.

## Networking

### Ingress

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Enable Kubernetes Ingress (to the api Service) | `false` |
| `ingress.className` | Ingress class name | `""` |
| `ingress.annotations` | Ingress annotations | `{}` |
| `ingress.hosts` | Ingress host rules | see values.yaml |
| `ingress.tls` | Ingress TLS configuration | `[]` |

Responses stream, so raise the proxy read timeout (ingress-nginx:
`nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"`).

### Istio / Big Bang

| Parameter | Description | Default |
|-----------|-------------|---------|
| `istio.enabled` | Enable Istio VirtualService | `false` |
| `istio.corveil.gateways` | Istio gateways | `["istio-system/public"]` |
| `istio.corveil.hosts` | VirtualService hosts | `["corveil.{{ .Values.domain }}"]` |
| `istio.mtls.mode` | mTLS mode | `STRICT` |

### NetworkPolicy

| Parameter | Description | Default |
|-----------|-------------|---------|
| `networkPolicy.enabled` | Enable NetworkPolicy | `false` |
| `networkPolicy.additionalEgressRules` | Additional egress rules | `[]` |

The policy selects every Corveil pod in the release (api, workers, system jobs). It allows
inbound on 8000 (api) and the workers health port, and outbound DNS, PostgreSQL (5432) and
HTTPS (443) for providers and sensors. Sensors that reach other ports (for example a Jira Data
Center on 8080) need `additionalEgressRules`.

### Service

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.type` | Kubernetes Service type (api) | `ClusterIP` |
| `service.port` | Service port | `8000` |

## Pod Configuration

These apply to every Corveil pod.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `serviceAccount.create` / `annotations` / `name` | ServiceAccount (annotations for IRSA / workload identity) | `true` / `{}` / `""` |
| `podSecurityContext` | Pod-level security context | `{}` |
| `securityContext` | Container security context | `{capabilities: {drop: [ALL]}, runAsNonRoot: true, runAsUser: 1000, ...}` |
| `nodeSelector` / `tolerations` / `affinity` | Scheduling | `{}` / `[]` / `{}` |
| `podLabels` / `podAnnotations` | Extra labels / annotations | `{}` |

### Autoscaling and disruption (api)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `autoscaling.enabled` | HorizontalPodAutoscaler for the api | `false` |
| `autoscaling.minReplicas` / `maxReplicas` | Bounds | `1` / `3` |
| `autoscaling.targetCPUUtilizationPercentage` | Target CPU | `70` |
| `podDisruptionBudget.enabled` | PodDisruptionBudget for the api | `false` |
| `podDisruptionBudget.minAvailable` / `maxUnavailable` | Budget | `1` / — |
| `podDisruptionBudget.unhealthyPodEvictionPolicy` | Let drains evict api pods that are not Ready | `AlwaysAllow` |
| `api.affinity` | Affinity for api pods (overrides `affinity`) | `{}` |

## Escape Hatches

| Parameter | Description | Default |
|-----------|-------------|---------|
| `extraEnv` | Env for every Corveil container (api, workers, system jobs) | `[]` |
| `extraVolumes` | Volumes for every Corveil pod | `[]` |
| `extraVolumeMounts` | Mounts for every Corveil container | `[]` |

```yaml
extraEnv:
  - name: REQUEST_LOG_BODY_MAX_KB
    value: "64"
  - name: CORVEIL_WORKOS_API_KEY
    valueFrom:
      secretKeyRef:
        name: corveil-workos
        key: api-key
```

## Template-time checks

The chart fails `helm install` / `helm template` with an explanation, rather than deploy pods
that crash-loop or ignore a setting, when:

- `corveil.devAuth=true` without `environment=development`
- `environment` is not `development` and there is no `uiSessionSecret`, or no system database
  DSN (unless `existingSecret` is set)
- no database is configured, or both the bundled and external database are
- `license.enabled=true` without `org`, `orgId`, and a key + public key or `existingSecret`
- `knowledge.sensors.filesystem.enabled=true` without a `volume`
- a values key removed in chart 1.0.0 or 2.0.0 is still set (see CHANGELOG.md)
