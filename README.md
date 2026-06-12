# MLflow Helm Deployment

This repository contains a Helmfile-based deployment for MLflow on Kubernetes.

It provides:

- MLflow tracking server
- PostgreSQL backend for MLflow metadata
- auth database for MLflow OIDC permissions
- S3-compatible artifact storage support
- Keycloak/OIDC authentication with per-user MLflow permissions
- Environment-specific values for local/dev and production deployments

## Repository Structure

```text
.
├── charts
│   ├── mlflow          # MLflow Helm chart
│   └── mlflow-core     # Supporting chart for Postgres, secrets, etc.
├── environments
│   ├── dev
│   │   ├── values.yaml
│   │   ├── mlflow-values.yaml.gotmpl
│   │   └── mlflow-core-values.yaml.gotmpl
│   └── prod
│       ├── values.yaml
│       ├── mlflow-values.yaml.gotmpl
│       └── mlflow-core-values.yaml.gotmpl
├── helmfile.yaml
├── mise.toml
└── README.md
```

## Components

### MLflow

MLflow is deployed as the main application. It is configured with:

- a backend store URI for metadata
- an artifact root for model/run artifacts
- optional OIDC authentication
- ingress for external access

In production, MLflow should not use SQLite or local artifact storage. Use PostgreSQL and S3-compatible storage instead.

### MLflow Core

The `mlflow-core` chart contains supporting resources such as:

- PostgreSQL
- Kubernetes Secrets
- database connection strings
- object storage credentials
- OIDC client secrets

Keeping these resources separate from the main MLflow chart makes the deployment easier to reason about and avoids mixing application configuration with infrastructure/bootstrap resources.

These resources are configured via `environments/{environ}/mlflow-core-values.yaml`.

### PostgreSQL

MLflow uses PostgreSQL for tracking metadata.

When OIDC authentication is enabled, the auth plugin also needs a database for users, groups, sessions, and permissions. The recommended setup is:

```text
same Postgres instance
same Postgres user
separate databases
```

Example:

```text
mlflow-db-postgres        # MLflow tracking metadata
mlflow-auth-db-postgres   # OIDC plugin auth/permissions data
```

Avoid using the same database for both unless you have a specific reason.

### Object Storage

Artifacts should be stored in S3-compatible object storage.

For Garage, MinIO, AWS S3, or similar systems, configure:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
MLFLOW_S3_ENDPOINT_URL
```

The artifact root should look like:

```text
s3://<bucket>/<prefix>
```

Example:

```text
s3://mlflow/artifacts
```

### Keycloak / OIDC

This deployment supports MLflow authentication through the `mlflow-oidc-auth` plugin. This is done using the custom built image found in `images/mlflow-oidc/Dockerfile`.

The MLflow server must run with:

```text
--app-name oidc-auth
```

Users are authorized through Keycloak groups.

Typical groups:

```text
mlflow         # regular users
mlflow-admin   # administrators
```

Regular users may see parts of the admin UI, but backend permission checks still prevent unauthorized actions.

## Environment Variables

Secrets are read from a local `.env` file and injected into Kubernetes Secrets through Helmfile templates.

Create a local `.env` file by copying the `.env.tmpl` file that already has all the envs that need to be set.

Generate a stable OIDC secret key with:

```bash
openssl rand -hex 32
```

## Mise Setup

`mise` can be used to run the deployment through a variety of commands. Using `mise run <command>` with the available commands:

- lint-{environ}: lint the deployment
- tmpl-{environ}: template the yaml output
- sync-{environ}: apply the configuration and run the deployment
- destroy-{environ}: destroy the deployment
- clean-{environ}: destroy deployment and remove leftover namespaces

Where `{environ}` is the environment you want to use, dev or prod.

## Local Access

If ingress is disabled or you are testing locally:

```bash
kubectl port-forward -n mlflow svc/mlflow-mlflow 5000:5000
```

Then open:

```text
http://localhost:5000
```

## Keycloak Configuration

Create an OIDC client in Keycloak.

Recommended client settings:

```text
Client ID: mlflow
Client authentication: enabled
Standard flow: enabled
Direct access grants: enabled
```

Redirect URI:

```text
https://<mlflow-host>/callback
```

For local testing, add:

```text
http://localhost:5000/callback
```

Make sure the token or userinfo response contains a `groups` claim.

Recommended Keycloak group mapper:

```text
Mapper type: Group Membership
Token claim name: groups
Full group path: Off
Add to ID token: On
Add to access token: On
Add to userinfo: On
```

Expected claim (example):

```json
{
  "groups": ["mlflow"]
}
```

or:

```json
{
  "groups": ["mlflow-admin"]
}
```

## Useful Commands

Check pods:

```bash
kubectl get pods -n mlflow
```

View MLflow logs:

```bash
kubectl logs -n mlflow deploy/mlflow-mlflow -f
```

View Postgres logs:

```bash
kubectl logs -n mlflow statefulset/mlflow-core-postgres -f
```

Check rendered environment variables:

```bash
kubectl exec -n mlflow deploy/mlflow-mlflow -- env | sort
```

Check a generated secret:

```bash
kubectl get secret -n mlflow mlflow-oidc -o yaml
```

Decode a secret value:

```bash
kubectl get secret -n mlflow mlflow-oidc \
  -o jsonpath='{.data.users-db-uri}' | base64 -d
echo
```

## Troubleshooting

### `User is not allowed to login`

OIDC login worked, but the user was not in an allowed group.

Check that the Keycloak token or userinfo response includes:

```json
"groups": ["mlflow"]
```

or:

```json
"groups": ["mlflow-admin"]
```

Also verify these MLflow environment variables:

```text
OIDC_GROUPS_ATTRIBUTE=groups
OIDC_GROUP_NAME=mlflow
OIDC_ADMIN_GROUP_NAME=mlflow-admin
```

### `Failed to update user/groups`

The OIDC plugin could not write to its auth database.

Check:

```bash
kubectl exec -n mlflow deploy/mlflow-mlflow -- env | grep OIDC_USERS_DB_URI
```

The value should point to a reachable PostgreSQL database.
