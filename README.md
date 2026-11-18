# Corveil Helm Chart

Helm chart for [Corveil](https://github.com/corveil/corveil): an AI gateway (virtual keys,
spend tracking, guardrails, OpenAI- and Anthropic-compatible APIs) and an organizational
knowledge graph built from the tools your teams use.

It runs the whole product on your own Kubernetes cluster: the **api** (`corveil serve`), the
**workers** (`corveil workers`), and the scheduled **system jobs** as CronJobs. It works as a
standalone install and as a Big Bang package.

Chart `2.0.0` deploys Corveil **v0.5.20**.

## Quick start (evaluation)

```bash
kubectl create namespace corveil
kubectl -n corveil create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io --docker-username=<github-user> --docker-password=<token-with-read:packages>

helm install corveil oci://ghcr.io/corveil/corveil-helm/corveil-chart -n corveil \
  --set imagePullSecrets[0].name=ghcr-pull \
  --set corveil.environment=development \
  --set corveil.devAuth=true \
  --set corveil.uiBaseUrl=http://localhost:8000 \
  --set corveil.secretKey="$(openssl rand -hex 32)"

kubectl -n corveil port-forward svc/corveil 8000:8000
```

Open <http://localhost:8000/ui> and choose **Dev login**. You become the owner of a local
organization. From there, create an API key, connect a client, enable a sensor and apply a
license: **[docs/GETTING_STARTED.md](docs/GETTING_STARTED.md)** walks through each step.

Evaluation mode uses a bundled PostgreSQL and a dev login that anyone who can reach the UI can
use. Don't expose it.

## Prerequisites

- Kubernetes 1.27+ and Helm 3.10+
- Pull access to the private image `ghcr.io/corveil/corveil` (a `read:packages` token on an
  account Corveil has granted access)
- For production: PostgreSQL 16+ with pgvector and the three Corveil roles
  ([Database roles](docs/CONFIGURATION.md#database-roles))

## Documentation

- **[Getting Started](docs/GETTING_STARTED.md)**: on-prem quick start, then production
- **[Configuration Reference](docs/CONFIGURATION.md)**: every value, with the env var it sets
- **[Architecture Overview](docs/ARCHITECTURE_OVERVIEW.md)**: workloads, database roles,
  request flow
- **[CHANGELOG](CHANGELOG.md)**: upgrade notes (2.0.0 is a breaking release)

## Production

```bash
helm install corveil oci://ghcr.io/corveil/corveil-helm/corveil-chart -n corveil \
  -f examples/values-production.yaml
```

[`examples/values-production.yaml`](examples/values-production.yaml) uses an external database,
secrets from an existing Secret, TLS ingress, two api replicas, a PDB and a NetworkPolicy. Read
[Getting Started → Production](docs/GETTING_STARTED.md#production) first. Two v0.5 constraints
matter: production UI sign-in is WorkOS only, and per-org provider credentials need AWS KMS.

## Big Bang

```yaml
addons:
  corveil:
    enabled: true
    values:
      istio:
        enabled: true
        corveil:
          gateways:
            - "istio-system/public"
          hosts:
            - "corveil.bigbang.dev"
      imagePullSecrets:
        - name: ghcr-pull
      corveil:
        environment: production
        uiBaseUrl: "https://corveil.bigbang.dev"
      existingSecret: corveil-secrets   # DATABASE_URL, DATABASE_URL_SYSTEM, DATABASE_URL_PRIVILEGED, SECRET_KEY, UI_SESSION_SECRET
      postgresql:
        enabled: false
```

## Key values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `corveil.environment` | `development` (evaluation) or `production` | `development` |
| `corveil.devAuth` | Evaluation dev login (`development` only) | `false` |
| `corveil.secretKey` | Encryption / signing key (**required** unless `existingSecret`) | `""` |
| `corveil.uiSessionSecret` | UI session key (required outside `development`) | `""` |
| `corveil.uiBaseUrl` | Public UI origin | `""` |
| `existingSecret` | Bring your own Secret of env vars | `""` |
| `postgresql.enabled` | Bundled evaluation PostgreSQL | `true` |
| `externalDatabase.url` / `systemUrl` / `privilegedUrl` | The three role DSNs | `""` |
| `api.replicaCount` | api replicas | `1` |
| `workers.enabled` | Deploy the workers | `true` |
| `systemJobs.enabled` / `systemJobs.jobs.*` | System-job CronJobs | enabled |
| `knowledge.sensors.enabled` | Poll configured sensors | `false` |
| `knowledge.ontology.sensorBridge` | Turn sensor events into graph entities | `false` |
| `license.enabled` | Offline license | `false` |
| `providers.*` | Deployment-wide provider keys | `""` |
| `ingress.enabled` / `istio.enabled` | External access | `false` |

See [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for everything else.

## Database migrations

The api runs migrations at startup, under a Postgres advisory lock, as the privileged role.
The workers wait until the schema matches. Upgrades need no separate migration step.

## Uninstall

```bash
helm -n corveil uninstall corveil
kubectl -n corveil delete pvc data-corveil-postgresql-0   # bundled PostgreSQL only; deletes its data
```

## License

MIT License. See [LICENSE](LICENSE).
