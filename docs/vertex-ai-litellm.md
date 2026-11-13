# Gemini on Vertex AI through LiteLLM

fidfab's Fabro-native nodes run on **Gemini 3.8 Flash** and its independent code and security
reviews run on **Gemini 4 Carbon**, both served by Google Cloud Vertex AI. Fabro has no Vertex
AI provider of its own ([fabro#157](https://github.com/fabro-sh/fabro/issues/157)), so a local
[LiteLLM](https://docs.litellm.ai/) proxy translates Fabro's OpenAI-compatible requests to
Vertex AI, and Fabro's built-in
[LiteLLM provider](https://docs.fabro.sh/integrations/litellm) points at it.

```
Fabro server (host) ──Bearer LITELLM_API_KEY──▶ 127.0.0.1:4000 LiteLLM (Docker)
                                                   └─ service-account key ──▶ Vertex AI (global)
```

This guide covers the Google Cloud side (a dedicated project, least-privilege service
accounts, key expiry, spend and usage monitoring), the proxy, and the Fabro configuration.
Replace `PROJECT_ID`, `BILLING_ACCOUNT_ID`, and `NAME` throughout.

## 1. A dedicated Google Cloud project

A separate project for agent inference keeps its spend, quotas, audit logs, and permissions
apart from everything else.

```bash
gcloud projects create PROJECT_ID --name="Agent inference"
gcloud billing accounts list
gcloud billing projects link PROJECT_ID --billing-account=BILLING_ACCOUNT_ID
gcloud services enable aiplatform.googleapis.com --project=PROJECT_ID
gcloud config set project PROJECT_ID   # so gcloud calls are billed and quota-checked here
```

Both models are served from the `global` location
([Gemini 3.8 Flash](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/guides/gemini-3-8-flash),
[Gemini 4 Carbon](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/gemini/4-carbon)).
Without an explicit quota project, `gcloud`-authenticated test calls can land on a shared quota
and return `429`.

Billing and the Vertex AI API are not enough for Gemini 4 Carbon: Google makes it available
only to verified enterprise customers in select regions (see the model page above). The page
gives no self-service request path, so ask your Google Cloud account team if you are unsure.
`scripts/litellm-proxy.sh test` (section 6) is the check: `gemini-4-carbon: failed` with a
working `gemini-3.8-flash` means the project lacks access, and the Carbon review stages will
fail until it has it.

## 2. A role that can only run inference

The predefined `roles/aiplatform.user` grants far more than calling a model (datasets,
endpoints, pipelines). A custom role with the single permission needed for
`generateContent` / chat completions is enough
([Vertex AI access control](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/access-control)):

```bash
gcloud iam roles create modelInvoker --project=PROJECT_ID \
  --title="Model invoker" \
  --description="Call Gemini models; nothing else" \
  --permissions=aiplatform.endpoints.predict --stage=GA
```

If a call returns `403 Permission ... denied`, the error names the missing permission; add only
that one with `gcloud iam roles update modelInvoker --project=PROJECT_ID --add-permissions=...`.

## 3. One service account per person

Give each person running a proxy their own service account, so keys can be revoked and usage
attributed individually:

```bash
gcloud iam service-accounts create litellm-proxy-NAME --project=PROJECT_ID \
  --display-name="LiteLLM proxy (NAME)"
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:litellm-proxy-NAME@PROJECT_ID.iam.gserviceaccount.com" \
  --role="projects/PROJECT_ID/roles/modelInvoker" --condition=None
```

To let a teammate rotate their own key without any project-level rights, grant them
`roles/iam.serviceAccountKeyAdmin` on their service account only:

```bash
gcloud iam service-accounts add-iam-policy-binding \
  litellm-proxy-NAME@PROJECT_ID.iam.gserviceaccount.com \
  --member="user:NAME@example.com" --role="roles/iam.serviceAccountKeyAdmin"
```

## 4. Keys: allow them for this project, expire them in 90 days

Organizations created recently enforce `iam.disableServiceAccountKeyCreation`. Override it for
this project only, and at the same time make every new key expire after 90 days
([restricting service accounts](https://docs.cloud.google.com/organization-policy/restrict-service-accounts)):

```bash
cat > allow-keys.yaml <<EOF
name: projects/PROJECT_ID/policies/iam.disableServiceAccountKeyCreation
spec:
  rules:
  - enforce: false
EOF
cat > key-expiry.yaml <<EOF
name: projects/PROJECT_ID/policies/iam.serviceAccountKeyExpiryHours
spec:
  rules:
  - values:
      allowedValues:
      - 2160h
EOF
gcloud org-policies set-policy allow-keys.yaml
gcloud org-policies set-policy key-expiry.yaml
```

Organization policy changes can take up to 15 minutes to be enforced
([creating organization policies](https://docs.cloud.google.com/organization-policy/create-organization-policies)),
and a key created before then gets no expiry. Wait, and confirm the effective policy lists
`2160h` before creating the key:

```bash
gcloud org-policies describe iam.serviceAccountKeyExpiryHours --project=PROJECT_ID --effective
```

Then create the key directly into the proxy's config directory:

```bash
install -d -m 700 ~/.config/fidfab-litellm
gcloud iam service-accounts keys create ~/.config/fidfab-litellm/litellm-proxy.json \
  --iam-account=litellm-proxy-NAME@PROJECT_ID.iam.gserviceaccount.com
chmod 600 ~/.config/fidfab-litellm/litellm-proxy.json
gcloud iam service-accounts keys list \
  --iam-account=litellm-proxy-NAME@PROJECT_ID.iam.gserviceaccount.com
```

Before using the key, check that its `validBeforeTime` (`EXPIRES_AT`) is about 90 days out. The
expiry applies only to keys created under the policy: delete and recreate any key that shows
`9999-12-31T23:59:59Z`.

Put a rotation reminder about a week before the expiry: create the new key, restart the proxy
(`scripts/litellm-proxy.sh start`), run `scripts/litellm-proxy.sh test`, then delete the old
key with `gcloud iam service-accounts keys delete KEY_ID --iam-account=...`.

## 5. Monitor spend and usage

- **Budget alert**: Billing → Budgets & alerts → Create budget, scoped to `PROJECT_ID`, with
  email thresholds (for example 50 %, 90 %, 100 %). Budgets notify; they do not stop spend.
- **Model usage**: the Vertex AI model observability dashboard in the console shows requests,
  tokens, latency, and errors per model for the project.
- **Who called what** (optional): enable Data Access audit logs for the Vertex AI API under
  IAM & Admin → Audit Logs. Each request then records the calling service account, which with
  one account per person attributes usage. These logs are billed as Cloud Logging volume.
- **Quota**: both models run on
  [Standard pay-as-you-go](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/standard-paygo)
  capacity, which is shared; bursts can return `429 Resource exhausted`. LiteLLM retries, and
  Fabro retries the stage. Provisioned Throughput is the option for guaranteed capacity.

## 6. The proxy

`scripts/litellm-proxy.sh` runs LiteLLM in Docker with the model list in
`docker/litellm/config.yaml`:

```bash
scripts/litellm-proxy.sh init PROJECT_ID   # writes ~/.config/fidfab-litellm/proxy.env (mode 600)
scripts/litellm-proxy.sh start
scripts/litellm-proxy.sh status
scripts/litellm-proxy.sh test              # gemini-3.8-flash: ready / gemini-4-carbon: ready
```

`proxy.env` holds a freshly generated `LITELLM_MASTER_KEY`, `VERTEX_PROJECT`, and
`VERTEX_CREDENTIALS_FILE` (the key path inside the container). Pass a second argument to
`init` if the key file is not named `litellm-proxy.json`.

What the script does, and why:

- The image is pinned by digest (LiteLLM v1.109.1, non-root variant). LiteLLM packages and
  images were compromised in
  [March 2026](https://docs.litellm.ai/blog/security-update-march-2026) and
  [October 2026](https://docs.litellm.ai/blog/security-incident-oct-21-2026); never follow a
  moving tag. Before changing the digest, verify the signature
  ([LiteLLM image security](https://docs.litellm.ai/docs/proxy/docker_image_security)):

  ```bash
  cosign verify \
    --key https://raw.githubusercontent.com/BerriAI/litellm/e82a3c646908ba0a6ee0beddc4310d7a6cac4065/cosign.pub \
    ghcr.io/berriai/litellm-non_root@sha256:NEW_DIGEST
  ```

  and set it in the script (or `FIDFAB_LITELLM_IMAGE` to try it first).
- The port is bound to `127.0.0.1` only, the container runs as your uid, and only the config
  directory (read-only) and `config.yaml` (read-only) are mounted. The proxy keeps no
  database, so there is no UI or virtual-key store; the master key is the only client key.
  For several people sharing one proxy, use
  [LiteLLM virtual keys](https://docs.litellm.ai/docs/proxy/virtual_keys) instead.
- `--restart unless-stopped` brings it back after reboots and Docker restarts.

**DNS.** If the logs show `Failed to resolve 'oauth2.googleapis.com'`, Docker's embedded
resolver cannot reach your host's resolver (common with systemd-resolved). Either set
resolvers for all containers in `/etc/docker/daemon.json` and restart Docker:

```json
{ "dns": ["1.1.1.1", "1.0.0.1"] }
```

or start the proxy with `FIDFAB_LITELLM_DNS=1.1.1.1 scripts/litellm-proxy.sh start`.
`curl: (7)` from `test` means nothing is listening: the container is not running
(`scripts/litellm-proxy.sh status`, then `logs`).

**Migrating from a hand-started container**: `docker rm -f litellm-vertex` (or whatever it is
called), add `VERTEX_PROJECT` and `VERTEX_CREDENTIALS_FILE` to the existing `proxy.env` (or
move it aside and run `init`), then `scripts/litellm-proxy.sh start`. If the master key
changes, run `scripts/setup.sh litellm` again to update the Fabro secret.

## 7. Fabro

```bash
scripts/setup.sh litellm
```

adds to `~/.fabro/settings.toml`:

```toml
[llm.providers.litellm]
base_url = "http://localhost:4000/v1"
default_model = "vertex-gemini-3.8-flash"
enabled = true

[llm.providers.litellm.models."vertex-gemini-3.8-flash"]
display_name = "Gemini 3.8 Flash (Vertex AI)"
api_model = "gemini-3.8-flash"
limits = { context_tokens = 1048576, max_output_tokens = 65536 }
capabilities = { text = true, tools = true }
small_default = true

[llm.providers.litellm.models."vertex-gemini-4-carbon"]
display_name = "Gemini 4 Carbon (Vertex AI)"
api_model = "gemini-4-carbon"
limits = { context_tokens = 1048576, max_output_tokens = 65536 }
capabilities = { text = true, tools = true }
```

then stores the proxy master key as the `LITELLM_API_KEY` vault secret (read from
`proxy.env`), restarts the server, and runs `fabro model test --model <id> --tools` for both
models ([Fabro models](https://docs.fabro.sh/core-concepts/models)). `api_model` must equal a
`model_name` in `docker/litellm/config.yaml`.

Model selection in the workflows:

- Each `.fabro/workflows/*/workflow.toml` sets `[run.model]` to `vertex-gemini-3.8-flash` on
  `litellm`. It has to live there: `fabro run` does not send `[run]` settings from
  `settings.toml` to the server, so remove any `[run.model]` (for example the former DeepSeek
  one) from `settings.toml`.
- `components/carbon-review.fabro` and `components/carbon-security-review.fabro` set
  `provider="litellm", model="vertex-gemini-4-carbon"` on their review nodes
  ([node attributes](https://docs.fabro.sh/workflows/stages-and-nodes)). The verify-and-address
  passes after them stay on Claude Code (opus).

The `base_url` uses `localhost` because the Fabro server runs on the host and makes the model
calls itself; the sandbox containers never talk to the proxy. If you run the Fabro server in
Docker, point `base_url` at an address that container can reach (for example a shared Docker
network and `http://fidfab-litellm:4000/v1`).

Gemini 3.x models return thought signatures with tool calls; LiteLLM carries them in
`provider_specific_fields` and replays them on the next turn, which multi-step tool loops need.
