# Corveil Helm Chart

Helm chart for [Corveil AI Gateway](https://github.com/corveil/corveil) — a zero-trust AI gateway with spend tracking, guardrails, and OpenAI-compatible API.

Works as a standalone Kubernetes install **and** as a Big Bang package.

## Quick Start

```bash
helm install corveil oci://ghcr.io/corveil/corveil-helm/corveil-chart \
  --set corveil.secretKey="$(openssl rand -hex 32)" \
  --set corveil.environment=development \
  --set corveil.devLoginEnabled=true \
  --set providers.openrouter.apiKey="sk-or-xxx"
```

> **Note**: The flags above enable evaluation mode (development environment with dev login). See [Evaluation Mode](#evaluation-mode) for details.

Port-forward and open the UI:

```bash
kubectl port-forward svc/corveil 8000:8000
open http://localhost:8000/ui
```

Click **Dev Login** to get started immediately — no OIDC setup required.

## Prerequisites

- Kubernetes 1.23+
- Helm 3.10+
- **Pull access to the Corveil image.** The default image
  (`ghcr.io/corveil/corveil`) is a **private** package. Create an image pull
  secret and reference it so the cluster can pull it:

  ```bash
  kubectl create secret docker-registry corveil-ghcr \
    --docker-server=ghcr.io \
    --docker-username=<github-user> \
    --docker-password=<github-token-with-read:packages>

  helm install corveil oci://ghcr.io/corveil/corveil-helm/corveil-chart \
    --set imagePullSecrets[0].name=corveil-ghcr \
    ...
  ```

  Skip this only if you override `image.repository` to an image your cluster can already pull.

## Documentation

- **[Getting Started Guide](docs/GETTING_STARTED.md)** — End-to-end deployment walkthrough
- **[Configuration Reference](docs/CONFIGURATION.md)** — Complete values.yaml parameter reference
- **[Architecture Overview](docs/ARCHITECTURE_OVERVIEW.md)** — System design for operators

## Installation

### Evaluation Mode

For trying out Corveil before production deployment. Enables the dev login UI so you can create users and API keys without configuring OIDC.

```bash
helm install corveil oci://ghcr.io/corveil/corveil-helm/corveil-chart \
  --set corveil.secretKey="change-me" \
  --set corveil.environment=development \
  --set corveil.devLoginEnabled=true \
  --set providers.openrouter.apiKey="sk-or-xxx"
```

This deploys Corveil with the bundled PostgreSQL, development mode, and dev login enabled.

### Production (external database)

```bash
helm install corveil oci://ghcr.io/corveil/corveil-helm/corveil-chart \
  --set corveil.secretKey="$(openssl rand -hex 32)" \
  --set corveil.okta.enabled=true \
  --set corveil.okta.domain="company.okta.com" \
  --set corveil.okta.clientId="0oaXXX" \
  --set corveil.okta.clientSecret="secret" \
  --set corveil.okta.sessionSecret="$(openssl rand -hex 32)" \
  --set postgresql.enabled=false \
  --set externalDatabase.url="postgresql://user:pass@db-host:5432/citadel" \
  --set providers.openrouter.apiKey="sk-or-xxx"
```

### Big Bang

```yaml
# In your Big Bang values override:
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
      corveil:
        secretKey: "change-me"
      providers:
        openrouter:
          apiKey: "sk-or-xxx"
```

### Using an Existing Secret

If you manage secrets externally (Vault, Sealed Secrets, ESO), create a Kubernetes Secret with the expected keys and reference it:

```bash
helm install corveil oci://ghcr.io/corveil/corveil-helm/corveil-chart \
  --set existingSecret=my-corveil-secrets
```

Required keys in your secret: `DATABASE_URL`, `SECRET_KEY`. Optional: `OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY`, etc.

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Container image | `ghcr.io/corveil/corveil` |
| `image.tag` | Image tag (defaults to appVersion) | `""` |
| `corveil.secretKey` | Session signing key (**required**) | `""` |
| `corveil.environment` | `development`, `staging`, or `production` | `production` |
| `corveil.devLoginEnabled` | Enable dev login bypass | `false` |
| `corveil.logLevel` | Log level | `INFO` |
| `corveil.autoProvisionUsers` | Auto-create users from headers | `true` |
| `corveil.guardrails.enabled` | Enable guardrails | `true` |
| `corveil.passthrough.enabled` | Enable API key passthrough | `true` |
| `corveil.plugins.enabled` | Enable plugin system | `true` |
| `corveil.okta.enabled` | Enable Okta OIDC | `false` |
| `providers.openrouter.apiKey` | OpenRouter API key | `""` |
| `providers.anthropic.apiKey` | Anthropic API key | `""` |
| `providers.vertexai.projectId` | GCP project ID | `""` |
| `providers.bedrock.enabled` | Enable AWS Bedrock | `false` |
| `postgresql.enabled` | Deploy bundled PostgreSQL | `true` |
| `postgresql.auth.password` | PostgreSQL password | `"citadel"` |
| `externalDatabase.url` | External PostgreSQL URL | `""` |
| `redis.enabled` | Deploy bundled Redis | `false` |
| `istio.enabled` | Enable Istio VirtualService | `false` |
| `ingress.enabled` | Enable Kubernetes Ingress | `false` |
| `autoscaling.enabled` | Enable HPA | `false` |
| `existingSecret` | Use external Secret | `""` |

For the complete configuration reference, see [docs/CONFIGURATION.md](docs/CONFIGURATION.md).

## Client Configuration

### Claude Code

```bash
claude config set --global apiBaseUrl http://<corveil-host>:8000/v1
```

### OpenAI SDK / Python

```python
from openai import OpenAI
client = OpenAI(
    base_url="http://<corveil-host>:8000/v1",
    api_key="<your-corveil-api-key>",
)
```

### curl

```bash
curl http://<corveil-host>:8000/v1/chat/completions \
  -H "Authorization: Bearer <your-corveil-api-key>" \
  -H "Content-Type: application/json" \
  -d '{"model": "or-claude-sonnet-4.5 [EXTERNAL]", "messages": [{"role": "user", "content": "Hello"}]}'
```

## Database Migrations

Migrations run automatically inside the application on startup via the app's lifespan handler. The init container only waits for database connectivity before the main container starts — it does not run migrations.

The migration runner is idempotent and tracks state in a `schema_migrations` table.

## Uninstall

```bash
helm uninstall corveil
```

Note: The bundled PostgreSQL PVC is **not** deleted automatically. To fully clean up:

```bash
kubectl delete pvc data-corveil-postgresql-0
```

## License

MIT License — see [LICENSE](LICENSE) for details.
