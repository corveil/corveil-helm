# Architecture Overview

This document describes how Corveil runs on Kubernetes, for the operators and platform
engineers who deploy it with this chart. It covers Corveil v0.5 and chart 2.x.

## What is Corveil?

Corveil sits between your people and agents (Claude Code, OpenAI- and Anthropic-compatible
clients, Crow) and the LLM providers they use. It also builds an organizational knowledge
graph from the tools your teams work in.

- **AI gateway**: virtual API keys, so real provider keys stay in Corveil; per-org model
  catalogs, budgets, spend tracking and rate limits; guardrails on input and output; request
  logs and an audit trail. It speaks the OpenAI (`/v1/chat/completions`) and Anthropic
  (`/v1/messages`) APIs.
- **Knowledge layer**: sensors pull events from GitHub, Jira, Slack, Google Workspace,
  Microsoft 365, a mounted folder and more. The ontology turns them into entities and links that
  people query from the UI, the `corveil` CLI and MCP.
- **Control plane**: everything the admin UI does is also available as REST, as the
  `corveil control` CLI, and as MCP `control_*` tools.

## Workloads

```
                    Ingress / Istio
                          │
                          ▼
              ┌───────────────────────┐        clients: Claude Code, SDKs, UI,
              │  api  (Deployment)    │◀────── corveil CLI, MCP
              │  corveil serve :8000  │
              │  /v1  /api  /ui  /mcp │
              │  migrations at boot   │
              └──────────┬────────────┘
                         │                      LLM providers / sensor sources
┌──────────────────────┐ │ ┌─────────────────────────┐        ▲
│ workers (Deployment) │ │ │ system jobs (CronJobs)  │        │ HTTPS
│ corveil workers      │ │ │ corveil system-job <x>  │────────┤
│ sensors, ontology,   │ │ │ retention, catalog and  │        │
│ sessions, queue      │ │ │ pricing sync, graph     │        │
│ health :8081         │ │ │ maintenance             │        │
└─────────┬────────────┘ │ └────────────┬────────────┘        │
          │              ▼              │                     │
          │   ┌──────────────────────┐  │                     │
          └──▶│ PostgreSQL + pgvector│◀─┘    (workers and api also call out)
              │ corveil_app (RLS)    │
              │ corveil_system       │
              └──────────────────────┘
```

| Workload | Scaling | Notes |
|----------|---------|-------|
| **api** | Horizontal (`api.replicaCount`, HPA) | Stateless. The UI is compiled into the binary, so there is no Node sidecar and no CDN dependency. Runs migrations at startup under an advisory lock. |
| **workers** | One replica | Scheduled loops take a database leader lock. Uses `Recreate` on upgrade. Exits while the schema is behind its build. |
| **system jobs** | One CronJob per job | Each run starts the binary, runs one job against the system database pool, and exits. |

All state lives in PostgreSQL. Nothing needs Redis or a shared filesystem. The one exception
is the optional filesystem sensor's mounted volume.

## Database and tenant isolation

Corveil isolates organizations with PostgreSQL row-level security (RLS). Each workload
connects as a role that matches what it does:

| Role | DSN | Can |
|------|-----|-----|
| `corveil` (owner) | `DATABASE_URL_PRIVILEGED` | Own the schema; run migrations |
| `corveil_app` | `DATABASE_URL` | Read and write one org's rows per transaction (NOBYPASSRLS) |
| `corveil_system` | `DATABASE_URL_SYSTEM` | Cross-org reads and sweeps (BYPASSRLS): sign-in, staff views, system jobs |

Outside `development`, the api and workers refuse to start without the system pool. The
bundled evaluation database creates the same three roles on first boot. See
[CONFIGURATION.md](CONFIGURATION.md#database-roles) for the SQL.

## Request flow (gateway)

```
client ──▶ auth (API key, or session + allowed origin)
       ──▶ org + key policy: model allowlist, budgets, rate limits
       ──▶ input guardrails
       ──▶ provider router (org credential, or deployment-wide key) ──▶ provider
       ◀── output guardrails, spend accounting, request log
```

Passthrough mode forwards the client's own provider credential (`Authorization`) and
authenticates to Corveil with `x-citadel-api-key`, so a Claude subscription can run through
Corveil's logging and guardrails.

## Endpoints

| Path | What |
|------|------|
| `POST /v1/chat/completions`, `GET /v1/models` | OpenAI-compatible gateway |
| `POST /v1/messages`, `POST /v1/messages/count_tokens` | Anthropic-compatible gateway |
| `/api/*` | REST API behind the UI and the `corveil control` CLI (`corveil control openapi` prints the spec) |
| `/mcp` | MCP: `ontology_*` and `control_*` tools |
| `/ui` | Web UI |
| `GET /health` | Liveness. Reports status and build version. |
| `GET /health/ready` | Readiness: database, schema version, guardrails |
| workers `GET :8081/health` | Workers liveness. 503 if a worker loop has stalled. |

## Authentication

- **API keys** (`sk-citadel-…`, SHA-256 hashed at rest) authenticate gateway, CLI and MCP
  traffic in every mode.
- **UI sign-in** is WorkOS in production. Dev login (`DEV_AUTH`) is for evaluation and
  only works with `ENVIRONMENT=development`.
- **Offline license** (optional): a signed license, verified at boot by the api and workers,
  that grants entitlements to one org (ADR-0018).

## Security model

- Provider keys never reach clients. Per-org provider credentials are sealed with AWS KMS
  (`corveil.providerCredentialsKmsKeyArn`). Other stored secrets are encrypted with a key
  derived from `SECRET_KEY`.
- RLS keeps every request to its organization.
- Containers run as UID 1000 with all capabilities dropped.
- With `networkPolicy.enabled`, pods accept 8000 (api) and the workers health port, and egress
  DNS, PostgreSQL and HTTPS.
- Sensors cannot reach private networks unless `knowledge.sensors.allowPrivateNetworks` is set.

## Kubernetes resources

| Resource | Condition | Purpose |
|----------|-----------|---------|
| Deployment `corveil` | always | api |
| Deployment `corveil-workers` | `workers.enabled` | workers |
| CronJob `corveil-<job>` | `systemJobs.enabled` + per job | system jobs |
| Service `corveil` | always | api ClusterIP on 8000 |
| ConfigMap `<release>-env` | always | non-secret env |
| Secret `<release>-secrets` | no `existingSecret` | DSNs, `SECRET_KEY`, provider keys |
| Secret `<release>-license` | `license.enabled` without `existingSecret` | license + public key |
| Secret `<release>-db-init` | `postgresql.enabled` | first-boot roles and pgvector for the bundled DB |
| ServiceAccount | `serviceAccount.create` | pod identity (IRSA / workload identity) |
| Ingress / VirtualService | `ingress.enabled` / `istio.enabled` | external access |
| HPA, PDB | `autoscaling.enabled`, `podDisruptionBudget.enabled` | api scaling and availability |
| NetworkPolicy | `networkPolicy.enabled` | traffic policy for all Corveil pods |
| PostgreSQL StatefulSet | `postgresql.enabled` | bundled evaluation database |

## Migrations and upgrades

The api applies pending migrations (`/app/migrations` in the image) at startup, before it
listens. It runs them as `DATABASE_URL_PRIVILEGED`, under a Postgres advisory lock, and
records the result in `schema_migrations`. `/health/ready` reports `schema.applied` against
`schema.expected`. The workers check the same table and exit while it is behind. There is no
separate migration Job or `migrate` subcommand. A `helm upgrade` is enough: the new api
migrates, and the workers follow.
