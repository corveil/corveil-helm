# Changelog

All notable changes to the Corveil Helm chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-11-18

Brings the chart up to **Corveil v0.5.20** (`appVersion` `0.3.4` → `0.5.20`). Corveil is no
longer only an AI gateway: it runs as an api, a singleton workers daemon and scheduled system
jobs, isolates orgs with Postgres row-level security across three database roles, and
supports an offline license. The chart now deploys all of that. This is a breaking release,
so read **Upgrade** below.

### Added

- **Workers Deployment** (`corveil workers`, `workers.*`): sensors, ontology, sessions and the
  job queue. One replica, `Recreate` strategy, `/health` probe on `workers.healthPort` (8081).
  Pods are labeled `app.kubernetes.io/name: corveil-workers`, so the api Service and selector
  are unchanged.
- **System-job CronJobs** (`systemJobs.*`): 16 `corveil system-job <name>` jobs enabled by
  default (retention purges, `catalog_sync`, `pricing_sync`, graph maintenance, session
  derivation, worker-run sweeps), on the hosted service's schedules. Each can be toggled and
  rescheduled. Five object-storage sweeps ship disabled. SaaS billing jobs (Stripe, usage
  units, trial, Cursor and provider-admin reconciliation) are not included.
- **Database role DSNs**: `externalDatabase.systemUrl` (`DATABASE_URL_SYSTEM`, BYPASSRLS
  `corveil_system`) and `externalDatabase.privilegedUrl` (`DATABASE_URL_PRIVILEGED`, the schema
  owner, used for migrations). Corveil refuses to start outside `development` without the
  system DSN.
- **Bundled PostgreSQL gets the production role layout.** A first-boot init script
  (`<release>-db-init`) creates `pgvector`, `corveil_app` and `corveil_system`, and the chart
  wires all three DSNs. Before this, dev login failed with an RLS violation on `users`, and
  pgvector was never created (a non-superuser can't), so embeddings silently had no vector
  column.
- **Offline license** (`license.*`, ADR-0018): `CORVEIL_LICENSE_OFFLINE_ENABLED`, `_ORG`,
  `_ORG_ID`, and the key and public key mounted from a Secret at `/etc/corveil/license/`
  (`CORVEIL_LICENSE_KEY_FILE` / `_PUBLIC_KEY_FILE`), on api and workers. Closes the gap left by
  #15, which was closed but never landed in the templates. See the Known issues below.
- **Knowledge layer** (`knowledge.*`): `SENSORS_ENABLED`, `ONTOLOGY_SENSOR_BRIDGE`,
  `ONTOLOGY_SYNTHESIS_ENABLED`, `SESSIONS_ENABLED`, `ONTOLOGY_ENABLED` on the workers;
  `CORVEIL_SENSOR_ALLOW_PRIVATE_NETWORKS` and `CORVEIL_SENSOR_AMBIENT_CREDENTIALS`; and a
  filesystem sensor volume (`FILESYSTEM_SENSOR_ROOT`).
- **UI and session settings**: `corveil.uiBaseUrl` (`UI_BASE_URL`),
  `corveil.sessionAuthAllowedOrigins` (`SESSION_AUTH_ALLOWED_ORIGINS`, defaults to
  `uiBaseUrl`, needed for the UI chat), `corveil.trustedProxyIps` (`TRUSTED_PROXY_IPS`),
  `corveil.uiSessionExpiryHours`.
- `corveil.providerCredentialsKmsKeyArn` (`CORVEIL_PROVIDER_CREDS_KMS_KEY_ARN`): outside
  `development`, per-org provider credentials need it.
- `mcpRunner.allowedHosts` / `mcpRunner.internalSecret` (`MCP_RUNNER_*`).
- `api.*` block (`replicaCount`, `resources`, `extraEnv`, `podAnnotations`, `affinity`). A
  `startupProbe` covers the first-boot migrations.
- `podDisruptionBudget.unhealthyPodEvictionPolicy` (default `AlwaysAllow`). The minimum
  supported Kubernetes is now 1.27.
- `examples/values-evaluation.yaml` and `examples/values-production.yaml`. CI lints and renders
  both.
- Template-time checks for combinations Corveil refuses at boot: `devAuth` outside
  `development`; a non-development environment without `uiSessionSecret` or a system DSN;
  license without org, org ID or key; and others.

### Changed (BREAKING)

- **`corveil.environment` defaults to `development`** (was `production`). The chart defaults
  (bundled PostgreSQL, password `citadel`) were always evaluation-only, and now the default
  environment says so. NOTES.txt prints an EVALUATION MODE banner. **If you relied on the
  old default, set `corveil.environment=production` explicitly.**
- `replicaCount` → `api.replicaCount`; `resources` → `api.resources`.
- `corveil.devLoginEnabled` → `corveil.devAuth`. It now renders `DEV_AUTH`, the variable the
  app reads; `DEV_LOGIN_ENABLED` was ignored.
- The api container is named `api` and runs `args: ["/app/corveil", "serve"]` explicitly.
- The NetworkPolicy selects every Corveil pod (`app.kubernetes.io/part-of: corveil`) and drops
  the Redis egress rule.
- The bundled database's `DATABASE_URL` is now the `corveil_app` role (was the owner).

### Removed

Each removed key fails `helm template` with a message if it is still set.

- **Redis** subchart, `redis.*` and `externalRedis.*`. Corveil v0.5 never reads `REDIS_URL`.
- **`modelsConfig`** and the `<release>-models` ConfigMap (`MODELS_CONFIG_PATH`,
  `MODEL_CURATION_ENABLED`). v0.5 ships a curated catalog in the database and discovers
  models with `catalog_sync`.
- **`corveil.okta.*`** (`OKTA_*`). The app removed Okta sign-in.
- **`logging.requestBody` / `responseBody`** (`LOG_REQUEST_BODY` / `LOG_RESPONSE_BODY`), no
  longer read. Body capture is bounded by `REQUEST_LOG_BODY_MAX_KB`.
- **`corveil.guardrails.openaiModeration`** (`GUARDRAIL_OPENAI_MODERATION`), no longer read.

### Decisions on earlier tickets

- **#12 (migration Job)** stays not planned. `corveil serve` applies migrations at startup
  under an advisory lock as `DATABASE_URL_PRIVILEGED`, and v0.5.20 has no `migrate`
  subcommand. Workers wait for the schema.
- **#14 (OIDC / BYOK values)**: Okta is gone and v0.5 has no self-hosted OIDC, so there is no
  OIDC surface. Per-org provider credentials (BYOK) are reachable through
  `corveil.providerCredentialsKmsKeyArn`.
- **#17 (subcharts off by default)**: Redis is removed outright. PostgreSQL stays on by
  default as the evaluation database; `examples/values-production.yaml` turns it off.
- **corveil#3533 (CDN `assetPrefix`)**: the GHCR release image is built same-origin and serves
  the UI from the pod. The chart sets no `UI_ASSETS_CDN_BASE_URL`, and the install was
  verified loading `/ui/_next/static/*` from the api pod.

### Known issues (app-side, Corveil v0.5.20)

- `/health` and `corveil health` report `version: dev`. The GHCR release build passes no
  `VERSION` build-arg. The image tag and the `org.opencontainers.image.version` label are
  correct.
- With `license.enabled=true`, the api and workers refuse to start under the RLS role layout.
  The startup check that the licensed org exists reads `organizations` as `corveil_app`, which
  sees no rows without an org context. The chart wiring is verified up to that check: the
  files mount, the signature verifies, and `CORVEIL_LICENSE_ORG` is read.
- Production UI sign-in is WorkOS only. The app has no self-hosted OIDC or SAML login.

### Upgrade

1. Move `replicaCount` / `resources` under `api:`, and rename `corveil.devLoginEnabled` to
   `corveil.devAuth`. Remove `redis`, `externalRedis`, `modelsConfig`, `logging`,
   `corveil.okta` and `corveil.guardrails.openaiModeration`. `helm template` names any that
   remain.
2. Set `corveil.environment` explicitly. For `production`, add `corveil.uiSessionSecret` and an
   external database with the three roles (docs/CONFIGURATION.md, Database roles), or an
   `existingSecret` holding `DATABASE_URL`, `DATABASE_URL_SYSTEM` and `DATABASE_URL_PRIVILEGED`.
3. `helm upgrade` in place. The api Deployment selector is unchanged. The new api pod
   migrates the schema from v0.3.x, and the workers start once it has.
4. An evaluation install on the bundled PostgreSQL from 1.x has no `corveil_app` /
   `corveil_system` roles (init scripts only run on an empty volume). Reinstall it with a
   fresh PVC, or create the roles by hand.

## [1.0.0] - 2026-07-21

Rebrands the chart identity from **Citadel** to **Corveil**. This is a breaking
change: the chart name, rendered resource names, and user-facing values keys all
change. See the upgrade note below.

> ⚠️ **On-the-wire / auth contract is intentionally unchanged.** The Corveil app
> still speaks `citadel` on the wire, so these are **kept as-is**: the
> `apiKeyPrefix` default `sk-citadel`, the `x-citadel-api-key` passthrough header,
> every rendered environment-variable **name** (`API_KEY_PREFIX`, `SECRET_KEY`,
> `ENVIRONMENT`, …), and the bundled PostgreSQL `database` /
> `username` / `password` defaults (`citadel`). `helm template` renders the exact
> same env-var keys the app reads.

### Changed (BREAKING)

- **Chart name**: `citadel-chart` → `corveil-chart`. The published OCI artifact
  moves to `oci://ghcr.io/corveil/corveil-helm/corveil-chart`.
- **`fullnameOverride`**: `"citadel"` → `"corveil"`. Rendered resource names
  (Deployment, Service, ServiceAccount, Secret, ConfigMap, HPA, PDB,
  NetworkPolicy, VirtualService, test pod) change from `citadel*` to `corveil*`.
- **`nameOverride`**: `""` → `"corveil"`, so the `app.kubernetes.io/name` selector
  label is now `corveil` (was `citadel-chart`, i.e. `.Chart.Name`). This aligns the
  label with the resource names and with the `kubectl -l app.kubernetes.io/name=corveil`
  commands in the docs. Being a selector-label change, it carries the same
  immutable-selector caveat on in-place upgrades — see the Upgrade note.
- **Values block key**: top-level `citadel:` → `corveil:`. Every override keyed
  under `citadel:` moves accordingly (e.g. `citadel.secretKey` →
  `corveil.secretKey`, `citadel.okta.*` → `corveil.okta.*`).
- **Istio block key**: `istio.citadel:` → `istio.corveil:` (gateways/hosts).
- **Template helpers**: `citadel.*` named templates → `corveil.*`.
- **`image.repository`**: `ghcr.io/radiusmethod/citadel` → `ghcr.io/corveil/corveil`.
  The Corveil app image now publishes to the `corveil` GHCR org.
- **`appVersion`**: `0.2.1` → `0.3.4`, tracking the current Corveil app release.
- **Branding**: README, docs, `LICENSE` (© 2026 Corveil, Inc.), `SECURITY.md`,
  `CONTRIBUTING.md`, `CODEOWNERS`, and issue templates repointed to
  `corveil/corveil-helm` / `corveil/corveil` / Corveil.

### Removed

- **SocketZero JWT authentication** (`socketzero.*` values and the
  `TRUST_SOCKETZERO_JWT` / `SOCKETZERO_JWT_*` env vars). The current Corveil app
  binary does not consume these, so the block was dropped rather than carried as
  dead config; it can be reintroduced when the app ships SocketZero support.
- **Dead `corveil.databaseUrl` template helper** (unused; `DATABASE_URL` is built
  inline in the Secret).

### Added

- **Migration guards.** The chart now `fail`s at template time with a clear,
  actionable message if a stale `citadel:` / `istio.citadel:` / `socketzero:`
  override key is still present, and `corveil.secretKey` is `required` when
  `existingSecret` is unset. This turns the breaking key rename into a loud error
  instead of a silently mis-secreted deploy (an ignored `citadel.secretKey`
  rendering an empty `SECRET_KEY`). Safe to remove after the 1.x line.

### Upgrade

Because resource names change, an in-place `helm upgrade` will try to replace
resources. Recommended path:

1. Migrate `values.yaml` overrides: `citadel:` → `corveil:` and
   `istio.citadel:` → `istio.corveil:`. Env-var **names** are unchanged.
2. Update the install source to
   `oci://ghcr.io/corveil/corveil-helm/corveil-chart`.
3. Either **reinstall fresh** as the `corveil` release (recommended — the name
   change makes Helm create new resources and remove the old ones), **or** for an
   in-place `helm upgrade`, pin *both* old identifiers so the immutable Deployment
   selector does not change:
   `--set fullnameOverride=citadel --set nameOverride=citadel-chart`.
   `fullnameOverride` keeps the old resource names; `nameOverride` keeps the old
   `app.kubernetes.io/name: citadel-chart` selector label. Omitting `nameOverride`
   flips that label and `helm upgrade` fails with `field is immutable`. The
   bundled-PostgreSQL PVC (`data-<release>-postgresql-0`) is not renamed by this
   change.

## [0.2.1] - 2026-03-08

### Changed

- **Go runtime migration**: Removed Python/uvicorn command override and `PYTHONPATH` env var from deployment — the Go image's `CMD ["/app/citadel"]` is now used as the entrypoint
- **Init container**: Replaced Python/asyncpg database wait script with a lightweight `busybox` + `nc` TCP check (no longer pulls the full app image for the init container)
- **`passthrough.enabled`**: Default changed from `false` to `true` to match the Go app default
- **`guardrails.openaiModeration`**: Default changed from `false` to `true` to match the Go app default
- Bumped `appVersion` to `0.2.0`

### Added

- **`citadel.uiSessionSecret`** value: Exposes `UI_SESSION_SECRET` in the Helm secret so production deployments don't silently CrashLoop when the Go app rejects the default session secret
- **NOTES.txt**: Added post-install guidance for creating an API key and PVC cleanup reminder

### Fixed

- Docs: Removed unnecessary "Add Bitnami repo" step (chart uses OCI dependencies)
- Docs: Fixed health response format from `{"status": "healthy"}` to `{"status":"ok"}`
- Docs: Replaced Python `asyncpg` troubleshooting command with `curl` health check
- Docs: Updated image tag references from `0.1.0` to `0.2.0`
- Docs: Added `uiSessionSecret` to production hardening checklist

## [0.1.0] - 2025-03-03

### Added

- Initial Helm chart for Citadel AI Gateway
- Deployment with configurable replicas and autoscaling (HPA)
- Bundled PostgreSQL via Bitnami subchart
- Bundled Redis via Bitnami subchart (optional)
- External database support
- Init container to wait for database readiness
- ConfigMap-based application configuration
- Secret management with `existingSecret` support for Vault/ESO
- Configurable models via `models.yaml` ConfigMap
- LLM provider configuration: OpenRouter, Anthropic, Vertex AI, AWS Bedrock
- Okta/OIDC authentication support
- Guardrails configuration (OpenAI moderation, PII filter)
- Plugin system toggle
- API key passthrough mode
- Kubernetes Ingress support
- Istio VirtualService for Big Bang integration
- ServiceAccount with configurable annotations
- Security context defaults (non-root, drop all capabilities)
- Helm test for health endpoint verification
- CI workflows for linting and OCI chart releases
