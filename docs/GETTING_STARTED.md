# Getting Started: Corveil on Kubernetes (on-prem)

This guide installs Corveil v0.5 on your own Kubernetes cluster with this Helm chart. It
covers an **evaluation install** you can bring up in about ten minutes, and then what changes
for **production**.

## What gets deployed

One image (`ghcr.io/corveil/corveil`) runs as three workloads:

| Workload | Kind | Command | What it does |
|----------|------|---------|--------------|
| **api** | Deployment `corveil` | `corveil serve` | AI gateway (`/v1`), REST API, the embedded web UI (`/ui`). Runs database migrations at startup. |
| **workers** | Deployment `corveil-workers` | `corveil workers` | Sensors, the knowledge graph (ontology), session derivation, scheduled loops, the job queue. |
| **system jobs** | CronJobs `corveil-<job>` | `corveil system-job <name>` | Retention purges, model catalog and pricing sync, graph maintenance. |

Plus, for evaluation, a bundled PostgreSQL (Bitnami) with pgvector. The UI is compiled into
the binary and served from the api pod. It does not need the Corveil CDN or any other
external asset host.

## Prerequisites

- A Kubernetes cluster (1.27+) and `kubectl` pointed at it. For a laptop,
  [k3d](https://k3d.io) or [kind](https://kind.sigs.k8s.io) work.
- [Helm](https://helm.sh) 3.10+.
- The `corveil` CLI, from the [Corveil releases](https://github.com/corveil/corveil/releases)
  (`corveil --help` should list `health`, `whoami` and `env`).
- **Pull access to the Corveil image.** `ghcr.io/corveil/corveil` is a private GHCR package.
  Corveil grants your GitHub account (or a machine user) read access. Then create a token with
  the `read:packages` scope and a pull secret in the namespace you install into:

  ```bash
  kubectl create namespace corveil

  kubectl -n corveil create secret docker-registry ghcr-pull \
    --docker-server=ghcr.io \
    --docker-username=<github-user> \
    --docker-password=<token-with-read:packages>
  ```

- Optionally, an LLM provider API key (Anthropic, OpenRouter, Vertex AI or Bedrock). You need
  one to send model traffic through the gateway. You can add it now or later.

## 1. Install in evaluation mode

Evaluation mode is `corveil.environment=development` with `corveil.devAuth=true`. It gives you
a **dev login** that signs you in as the owner of a local organization, with no SSO to set up.
Anyone who can reach the UI can use dev login, so keep the UI behind `kubectl port-forward`
and don't expose an evaluation install on a network.

```bash
helm install corveil oci://ghcr.io/corveil/corveil-helm/corveil-chart \
  --namespace corveil \
  --set imagePullSecrets[0].name=ghcr-pull \
  --set corveil.environment=development \
  --set corveil.devAuth=true \
  --set corveil.uiBaseUrl=http://localhost:8000 \
  --set corveil.secretKey="$(openssl rand -hex 32)"
```

The same settings are in [`examples/values-evaluation.yaml`](../examples/values-evaluation.yaml).

| Setting | Why |
|---------|-----|
| `imagePullSecrets[0].name` | The pull secret from the prerequisites. |
| `corveil.environment=development` | Evaluation mode. It is also the chart default. |
| `corveil.devAuth=true` | Enables `/auth/dev-login`. Corveil refuses to start with it outside `development`. |
| `corveil.uiBaseUrl` | The origin you open the UI on. It also allows the UI's chat to call `/v1` with your session. |
| `corveil.secretKey` | Encrypts stored credentials and signs tokens. Keep the same value across upgrades. |

The bundled PostgreSQL creates pgvector and three database roles on first boot, the same
layout production uses (see [Database roles](CONFIGURATION.md#database-roles)).

## 2. Check that it is running

```bash
kubectl -n corveil get pods
```

You should see `corveil-…`, `corveil-workers-…` and `corveil-postgresql-0` all `1/1 Running`
within a few minutes. On the first install the api pod runs about 400 migrations before it
becomes Ready. Until it finishes, the workers pod exits with `database schema is behind` and
restarts once or twice. That is expected.

The system jobs are CronJobs. The first ones (`crow-session-derive`, `gateway-session-derive`)
run within five minutes:

```bash
kubectl -n corveil get cronjobs
```

Port-forward the api and check health:

```bash
kubectl -n corveil port-forward svc/corveil 8000:8000
```

In another terminal:

```bash
curl -s http://localhost:8000/health
# {"status":"ok","version":"dev"}

curl -s http://localhost:8000/health/ready
# {"status":"ok","ready":true,"database":"ok","schema":{"state":"ok","applied":410,"expected":410,...},...}
```

`schema.applied` equal to `schema.expected` means migrations are complete.

> **Known issue: `version` reads `dev`.** The v0.5.x images on GHCR are built without a
> version stamp, so `/health` and `corveil health` report `dev`. Check the running version from
> the image tag instead:
> `kubectl -n corveil get deploy corveil -o jsonpath='{.spec.template.spec.containers[0].image}'`.

## 3. Sign in and create your first organization

Open <http://localhost:8000/ui> and choose **Dev login**. The first dev login creates an
organization named `corveil.local` and makes you its **owner**, so you have every admin
capability. You land on the dashboard's **Connect** page.

## 4. Create an API key

In the UI, open **API Keys** and create a key. Copy it: it starts with `sk-citadel-` and is
shown only once. (`sk-citadel` is Corveil's key format, kept from the product's earlier name.)

Point the CLI at your install and check it:

```bash
export CORVEIL_URL=http://localhost:8000
export CORVEIL_API_KEY=sk-citadel-...

corveil health
# {"build":{...,"version":"dev"},"status":"ok","version":"dev"}

corveil whoami
# {"org_id":"3b95deba-…","org_name":"corveil.local","org_status":"active",...}
```

Keep `org_id`: you need it to apply a license.

## 5. Connect a client

The gateway needs a provider credential before it can serve a model. Use either method:

- **Per organization (UI):** in **Governance → AI Gateway**, an org admin adds a provider key
  (Providers) and enables models (Models).
- **Deployment-wide (Helm):** every org can use the key. For example:

  ```bash
  helm upgrade corveil oci://ghcr.io/corveil/corveil-helm/corveil-chart -n corveil \
    --reuse-values --set providers.anthropic.apiKey=sk-ant-...
  ```

See which models your key can use:

```bash
curl -s http://localhost:8000/v1/models -H "Authorization: Bearer $CORVEIL_API_KEY"
```

**Claude Code.** `corveil env` prints the exports for your install:

```bash
# Managed inference through Corveil, using the provider credential above:
eval "$(corveil env claude-code --mode direct)" && claude

# Or bring your own `claude login` subscription. Corveil logs it and applies guardrails:
eval "$(corveil env claude-code)" && claude
```

**OpenAI-compatible clients:**

```bash
curl -s http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $CORVEIL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"<a model id from /v1/models>","messages":[{"role":"user","content":"Say hello in five words."}]}'
```

```python
from openai import OpenAI
client = OpenAI(base_url="http://localhost:8000/v1", api_key="sk-citadel-...")
print(client.chat.completions.create(
    model="<a model id from /v1/models>",
    messages=[{"role": "user", "content": "Hello"}],
).choices[0].message.content)
```

Each request shows up in the UI's logs and analytics, with spend and any guardrail actions.

## 6. Enable a sensor

Sensors pull events from your tools (GitHub, Jira, Slack, Google Drive, a mounted folder, and
more) into Corveil's knowledge graph. They run on the workers Deployment and are off by
default. Turn on polling and the sensor-to-graph bridge:

```bash
helm upgrade corveil oci://ghcr.io/corveil/corveil-helm/corveil-chart -n corveil \
  --reuse-values \
  --set knowledge.sensors.enabled=true \
  --set knowledge.ontology.sensorBridge=true
```

The workers log `sensor poll handler enabled` when the change is live. Then add a sensor in the UI:

1. Open **Corvus → Sensors** and choose **Add sensor**.
2. Pick **GitHub**, give it a token that can read the repositories you choose, and select them.
3. Save. The sensor's first poll backfills the last 72 hours.

Check progress from the CLI:

```bash
corveil sensors list
corveil stats            # entity counts and sensor status for your org
corveil search "<a repository name>"
```

Sources on your private network (GitHub Enterprise Server, Jira Data Center) are blocked by
default. Set `knowledge.sensors.allowPrivateNetworks=true` on a single-tenant install to allow
them. To read files from a mounted volume, see
[Filesystem sensor](CONFIGURATION.md#filesystem-sensor).

Synthesis (`knowledge.ontology.synthesis`), the LLM pass that writes knowledge pages for
entities, runs on a Crow worker runner. This chart does not deploy one.

## 7. Apply a license

Self-hosted entitlements come from an **offline license**: a signed key Corveil issues to your
organization, plus the public key to verify it. Boot fails closed if the license is invalid,
expired or for the wrong org.

> **Known issue (v0.5.20): don't enable the license yet.** The startup check that the licensed
> organization exists runs as the RLS-restricted `corveil_app` role, so it can't see any
> organization. With `license.enabled=true`, the api and workers refuse to start with
> `CORVEIL_LICENSE_ORG_ID … does not match any organization`. The steps below are correct for
> the chart and will work once Corveil ships the fix. Until then, leave `license.enabled=false`.

```bash
kubectl -n corveil create secret generic corveil-license \
  --from-file=license.jwt=./license.jwt \
  --from-file=public.pem=./corveil_public.pem

helm upgrade corveil oci://ghcr.io/corveil/corveil-helm/corveil-chart -n corveil \
  --reuse-values \
  --set license.enabled=true \
  --set license.existingSecret=corveil-license \
  --set license.org="<organization name on the license>" \
  --set license.orgId="<org_id from corveil whoami>"
```

The Secret is mounted at `/etc/corveil/license/` in the api and workers pods. A renewed
license written to the same Secret is picked up within `license.revalidateInterval`
(default 1h), without a restart.

## Production

An evaluation install is not a production install. For production, change the following.

**Database.** Use a managed or HA PostgreSQL 16+ with pgvector, and set
`postgresql.enabled=false`. Create the three roles in
[Database roles](CONFIGURATION.md#database-roles) and supply all three DSNs:

| DSN | Role | Used for |
|-----|------|----------|
| `DATABASE_URL` | `corveil_app` (NOBYPASSRLS) | Every request. Row-level security scopes it to one org. |
| `DATABASE_URL_SYSTEM` | `corveil_system` (BYPASSRLS) | Cross-org system reads in the api, workers and system jobs. **Required**: outside `development`, Corveil refuses to start without it. |
| `DATABASE_URL_PRIVILEGED` | `corveil` (schema owner) | Migrations, run by the api at startup. |

**Environment and secrets.** Set `corveil.environment=production` and leave `corveil.devAuth`
false. Keep secrets out of values files with `existingSecret`: a Secret whose keys are the env
names (`DATABASE_URL`, `DATABASE_URL_SYSTEM`, `DATABASE_URL_PRIVILEGED`, `SECRET_KEY`,
`UI_SESSION_SECRET`, and any provider keys). Generate secrets with `openssl rand -hex 32`.

**Sign-in.** In v0.5, the only sign-in for production is WorkOS, a hosted identity service.
Dev login is evaluation-only, and v0.5 has no self-hosted OIDC or SAML login. Talk to Corveil
before planning a production install without WorkOS.

**Provider credentials.** Outside `development`, the per-org provider credentials that org
admins add in the UI are sealed with AWS KMS. Set `corveil.providerCredentialsKmsKeyArn` and
give the pods AWS credentials (for example IRSA through `serviceAccount.annotations`).
Without it, per-org credentials are off and only the deployment-wide keys under `providers`
work.

**Network.**
- Expose the api through an Ingress with TLS (`ingress.*`), or through Istio (`istio.*`).
- Set `corveil.uiBaseUrl` to the public origin.
- Set `corveil.trustedProxyIps` to your ingress controller's addresses, so per-IP rate limits
  see the real client and not the proxy.
- Allow long-lived responses: chat completions stream. With ingress-nginx, raise
  `proxy-read-timeout`.

**Availability.**
- Run two or more api replicas (`api.replicaCount`, or `autoscaling.*`) with
  `podDisruptionBudget.enabled=true`. Migrations take an advisory lock, so replicas starting
  together are safe.
- Leave the workers at one replica.
- Back up the database. All of Corveil's state is in PostgreSQL.

**Upgrades.** `helm upgrade` with a new chart version rolls the api first: the new api pod
migrates the schema on startup. The workers use the `Recreate` strategy and restart until the
schema matches their build. No separate migration Job is needed. Pin `image.tag` only if you
must run a version other than the chart's `appVersion`.

A complete example is in [`examples/values-production.yaml`](../examples/values-production.yaml):

```bash
helm install corveil oci://ghcr.io/corveil/corveil-helm/corveil-chart -n corveil \
  -f examples/values-production.yaml
```

The chart checks the combination at template time. For example, it fails with a clear message
if `environment=production` is missing `uiSessionSecret` or a system database DSN.

## Upgrading from chart 1.x

Chart 2.0.0 is a breaking release. Read [CHANGELOG.md](../CHANGELOG.md#200---2026-11-18). In
short: `replicaCount` / `resources` moved under `api.`; `corveil.devLoginEnabled` is now
`corveil.devAuth`; the `redis`, `modelsConfig`, `logging` and `corveil.okta` values were
removed because Corveil v0.5 no longer reads them. The chart fails with a message naming any
removed key still in your values.

An evaluation install on the bundled PostgreSQL from chart 1.x doesn't have the
`corveil_app` / `corveil_system` roles, because the init script only runs on an empty volume.
Reinstall it:

```bash
helm -n corveil uninstall corveil
kubectl -n corveil delete pvc data-corveil-postgresql-0
```

Alternatively, create the roles by hand with the SQL in
[Database roles](CONFIGURATION.md#database-roles).

## Troubleshooting

**`ImagePullBackOff`**: the pull secret is missing, in another namespace, or its token can't
read `ghcr.io/corveil/corveil`. Check `kubectl -n corveil describe pod <pod>`.

**Workers in `CrashLoopBackOff` with `database schema is behind`**: the api hasn't finished
migrating. Wait for the api pod to be Ready. If it stays this way, check the api logs for
`database migration failed`.

**`new row violates row-level security policy`, or `password authentication failed for user
"corveil_app"`**: the database doesn't have the Corveil roles, typically a bundled database
created by chart 1.x. See [Upgrading from chart 1.x](#upgrading-from-chart-1x).

**`helm install` fails with `corveil.devAuth=true requires corveil.environment=development`**,
or another chart message: these come from the chart's own checks. Each names the setting to
change.

**Readiness never passes**: `curl -s localhost:8000/health/ready` lists the failing check
(`database`, `schema`, …).

**Logs:**

```bash
kubectl -n corveil logs deploy/corveil
kubectl -n corveil logs deploy/corveil-workers
kubectl -n corveil logs job/<job-name>          # a system-job run
```

**Uninstall.** The bundled PostgreSQL's volume survives `helm uninstall`. Delete it to start
fresh:

```bash
helm -n corveil uninstall corveil
kubectl -n corveil delete pvc data-corveil-postgresql-0
```
