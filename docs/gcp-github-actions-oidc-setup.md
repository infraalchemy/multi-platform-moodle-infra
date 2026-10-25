# GitHub Actions OIDC / Workload Identity Federation Setup

Google recommends Workload Identity Federation instead of storing a long-lived service-account JSON key in GitHub.

GitHub Actions will authenticate to Google Cloud using OIDC, impersonate a dedicated service account, obtain GKE credentials, and then run the existing deployment scripts.

## 1. Confirm the GitHub repository identity

From the repository directory:

```bash
git remote get-url origin
```

Expected:
```text
https://github.com/infraalchemy/multi-platform-moodle-infra.git
```

Therefore:
```text
GitHub owner: infraalchemy
Repository: infraalchemy/multi-platform-moodle-infra
```

## 2. Set the local variables

```bash
PROJECT_ID="civic-champion-439320-a5"
GITHUB_ORG="infraalchemy"
REPO="infraalchemy/multi-platform-moodle-infra"

SERVICE_ACCOUNT="github-actions"
POOL="github"
PROVIDER="cloud-infra-single-node"
```

Set the active GCP project:

```bash
gcloud config set project "$PROJECT_ID"
```

## 3. Create the GitHub Actions service account

```bash
gcloud iam service-accounts create "$SERVICE_ACCOUNT" \
  --project="$PROJECT_ID" \
  --display-name="GitHub Actions GKE Deployment"
```

Service-account email:
```text
github-actions@civic-champion-439320-a5.iam.gserviceaccount.com
```

Grant the service account access required by the deployment pipeline.
```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/container.developer"
```

```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/container.clusterViewer"
```

```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"
```

These permissions allow the GitHub Actions service account to interact with GKE and Artifact Registry.

## 4. Create the Workload Identity Pool

```bash
gcloud iam workload-identity-pools create "$POOL" \
  --project="$PROJECT_ID" \
  --location="global" \
  --display-name="GitHub Actions Pool"
```

Expected:
```text
Created workload identity pool [github].
```

Get the full Workload Identity Pool resource name:
```bash
WORKLOAD_IDENTITY_POOL_ID=$(gcloud iam workload-identity-pools describe "$POOL" \
  --project="$PROJECT_ID" \
  --location="global" \
  --format="value(name)")
```

Verify:
```bash
echo "$WORKLOAD_IDENTITY_POOL_ID"
```

Expected:
```text
projects/1006034492977/locations/global/workloadIdentityPools/github
```

## 5. Create the GitHub OIDC provider

Create an OIDC provider inside the Workload Identity Pool.

```bash
gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="$POOL" \
  --display-name="GitHub OIDC Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository_owner == 'infraalchemy'" \
  --issuer-uri="https://token.actions.githubusercontent.com"
```

The attribute condition restricts authentication to repositories owned by:

```text
infraalchemy
```

### Issue encountered

The original display name was:

```text
cloud-infra-single-node GitHub Provider
```

Google rejected it because Workload Identity Provider display names are limited to 32 characters.

The shorter name was used instead:

```text
GitHub OIDC Provider
```

Verify the provider's attribute condition:
```bash
gcloud iam workload-identity-pools providers describe "cloud-infra-single-node" \
  --project="civic-champion-439320-a5" \
  --location="global" \
  --workload-identity-pool="github" \
  --format="yaml(displayName,attributeMapping,attributeCondition,oidc)"
```

Expected:

assertion.repository_owner == 'infraalchemy'


## 6. Allow the GitHub repository to impersonate the service account

Grant the specific GitHub repository permission to impersonate the `github-actions` service account:
```bash
gcloud iam service-accounts add-iam-policy-binding \
  "github-actions@civic-champion-439320-a5.iam.gserviceaccount.com" \
  --project="civic-champion-439320-a5" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/1006034492977/locations/global/workloadIdentityPools/github/attribute.repository/infraalchemy/cloud-infra-single-node"
```

This establishes the trust path:
```text
infraalchemy/cloud-infra-single-node
        ↓
GitHub OIDC identity
        ↓
Google Workload Identity Pool
        ↓
github-actions service account
        ↓
GCP / GKE permissions
```

Only the specified GitHub repository is granted this service-account impersonation binding.

There's also the cleanup command we haven't finished documenting because it only applies to our live setup, not a clean installation. We need to remove:

YOUR_GITHUB_USERNAME/cloud-infra-single-node

from the service account, then verify only infraalchemy/cloud-infra-single-node remains.

So I'd distinguish the two:

Clean installation runbook: Steps 1–9 I gave you + provider verification above.
Our current environment: one additional cleanup of the accidental placeholder binding.

## 7. Verify the service-account IAM binding

```bash
gcloud iam service-accounts get-iam-policy \
  "github-actions@civic-champion-439320-a5.iam.gserviceaccount.com" \
  --project="civic-champion-439320-a5"
```

The `roles/iam.workloadIdentityUser` member should include:
```text
principalSet://iam.googleapis.com/projects/1006034492977/locations/global/workloadIdentityPools/github/attribute.repository/infraalchemy/cloud-infra-single-node
```

## 8. Get the provider name for GitHub Actions

```bash
gcloud iam workload-identity-pools providers describe "$PROVIDER" \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="$POOL" \
  --format="value(name)"
```

Expected:
```text
projects/1006034492977/locations/global/workloadIdentityPools/github/providers/cloud-infra-single-node
```

This value will be used by the GitHub Actions workflow as the Workload Identity Provider.

The workflow will also require:
```yaml
permissions:
  contents: read
  id-token: write
```

`id-token: write` allows GitHub Actions to request the short-lived OIDC token used to authenticate to Google Cloud.

## 9. Next Step

Create:
```text
.github/workflows/deploy-moodle.yml
```

The workflow will:

```text
GitHub Actions
      ↓
OIDC / Workload Identity Federation
      ↓
Google Cloud authentication
      ↓
GKE credentials
      ↓
check-moodle-image.sh
      ↓
deploy-moodle-gke.sh
      ↓
rollout verification
```

The existing working deployment scripts remain responsible for deployment logic. GitHub Actions only orchestrates them.


Verify:

For the OIDC setup we just did, I’d verify these four things before touching the workflow:

Provider condition:
```bash
gcloud iam workload-identity-pools providers describe "cloud-infra-single-node" \
  --project="civic-champion-439320-a5" \
  --location="global" \
  --workload-identity-pool="github" \
  --format="yaml(displayName,attributeMapping,attributeCondition,oidc)"
```

Confirm you see:

assertion.repository_owner == 'infraalchemy'

and the mappings include:

attribute.repository
attribute.repository_owner
Service-account trust binding
gcloud iam service-accounts get-iam-policy \
  "github-actions@civic-champion-439320-a5.iam.gserviceaccount.com" \
  --project="civic-champion-439320-a5"

Confirm the repo binding is:

.../attribute.repository/infraalchemy/cloud-infra-single-node

and that the old YOUR_GITHUB_USERNAME/... entry is gone.

Project roles on the service account
gcloud projects get-iam-policy "civic-champion-439320-a5" \
  --flatten="bindings[].members" \
  --filter="bindings.members:github-actions@civic-champion-439320-a5.iam.gserviceaccount.com" \
  --format="table(bindings.role)"

We want to see the roles we granted, especially:

roles/container.developer
roles/container.clusterViewer
roles/artifactregistry.writer
Provider resource name
gcloud iam workload-identity-pools providers describe "cloud-infra-single-node" \
  --project="civic-champion-439320-a5" \
  --location="global" \
  --workload-identity-pool="github" \
  --format="value(name)"

Expected:

projects/1006034492977/locations/global/workloadIdentityPools/github/providers/cloud-infra-single-node