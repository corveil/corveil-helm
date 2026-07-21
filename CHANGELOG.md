# Changelog

All notable changes to the Corveil Helm chart will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-07-21

Rebrands the chart identity from **Citadel** to **Corveil**. This is a breaking
change: the chart name, rendered resource names, and user-facing values keys all
change. See the upgrade note below.

> ⚠️ **On-the-wire / auth contract is intentionally unchanged.** The Corveil app
> still speaks `citadel` on the wire, so these are **kept as-is**: the
> `apiKeyPrefix` default `sk-citadel`, the `x-citadel-api-key` passthrough header,
> every rendered environment-variable **name** (`API_KEY_PREFIX`, `SECRET_KEY`,
> `SOCKETZERO_JWT_AUDIENCE`, …), and the bundled PostgreSQL `database` /
> `username` / `password` defaults (`citadel`). `helm template` renders the exact
> same env-var keys the app reads.

### Changed (BREAKING)

- **Chart name**: `citadel-chart` → `corveil-chart`. The published OCI artifact
  moves to `oci://ghcr.io/corveil/corveil-helm/corveil-chart`.
- **`fullnameOverride`**: `"citadel"` → `"corveil"`. Rendered resource names
  (Deployment, Service, ServiceAccount, Secret, ConfigMap, HPA, PDB,
  NetworkPolicy, VirtualService, test pod) change from `citadel*` to `corveil*`.
- **Values block key**: top-level `citadel:` → `corveil:`. Every override keyed
  under `citadel:` moves accordingly (e.g. `citadel.secretKey` →
  `corveil.secretKey`, `citadel.okta.*` → `corveil.okta.*`).
- **Istio block key**: `istio.citadel:` → `istio.corveil:` (gateways/hosts).
- **Template helpers**: `citadel.*` named templates → `corveil.*`.
- **`image.repository`**: `ghcr.io/radiusmethod/citadel` → `ghcr.io/corveil/corveil`.
  The Corveil app image now publishes to the `corveil` GHCR org.
- **`socketzero.jwtAudience`** default: `"citadel"` → `"corveil"`, matching the
  Corveil app's `SOCKETZERO_JWT_AUDIENCE` default.
- **`appVersion`**: `0.2.1` → `0.3.4`, tracking the current Corveil app release.
- **Branding**: README, docs, `LICENSE` (© 2026 Corveil, Inc.), `SECURITY.md`,
  `CONTRIBUTING.md`, `CODEOWNERS`, and issue templates repointed to
  `corveil/corveil-helm` / `corveil/corveil` / Corveil.

### Upgrade

Because resource names change, an in-place `helm upgrade` will try to replace
resources. Recommended path:

1. Migrate `values.yaml` overrides: `citadel:` → `corveil:` and
   `istio.citadel:` → `istio.corveil:`. Env-var **names** are unchanged.
2. Update the install source to
   `oci://ghcr.io/corveil/corveil-helm/corveil-chart`.
3. Either reinstall fresh as the `corveil` release, or set
   `--set fullnameOverride=citadel` to keep the old resource names during the
   transition. The bundled-PostgreSQL PVC (`data-<release>-postgresql-0`) is not
   renamed by this change.

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
