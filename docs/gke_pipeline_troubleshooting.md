
# GKE CI/CD Pipeline – Troubleshooting Notes

This document records the configuration issues, IAM permission errors, Terraform state migration, and Kubernetes deployment problems encountered while implementing GitHub Actions automation for GKE.

## 1. Workload Identity Federation and IAM

### Verify the Workload Identity Pool

Run in GCP Cloud Shell:

```bash
gcloud iam workload-identity-pools list \
  --location="global" \
  --project="civic-champion-439320-a5"
```

Expected result:

```yaml
displayName: GitHub Actions Pool
name: projects/1006034492977/locations/global/workloadIdentityPools/github
state: ACTIVE
```

### Verify the OIDC Provider

```bash
gcloud iam workload-identity-pools providers list \
  --workload-identity-pool="github" \
  --location="global" \
  --project="civic-champion-439320-a5"
```
Expected configuration:

```yaml
attributeCondition: assertion.repository_owner == 'infraalchemy'
attributeMapping:
  attribute.actor: assertion.actor
  attribute.repository: assertion.repository
  attribute.repository_owner: assertion.repository_owner
  google.subject: assertion.sub
displayName: GitHub OIDC Provider
name: projects/1006034492977/locations/global/workloadIdentityPools/github/providers/cloud-infra-single-node
oidc:
  issuerUri: https://token.actions.githubusercontent.com
state: ACTIVE
```


### Verify the GitHub Actions Service Account

```bash
gcloud iam service-accounts list \
  --project="civic-champion-439320-a5"
```

Recorded service accounts:

```text
DISPLAY NAME: Compute Engine default service account
EMAIL: 1006034492977-compute@developer.gserviceaccount.com
DISABLED: False

DISPLAY NAME: GitHub Actions GKE Deployment
EMAIL: github-actions@civic-champion-439320-a5.iam.gserviceaccount.com
DISABLED: False
```
---

## 2. IAM Permission Errors

### Project Service API – HTTP 403

**Error encountered:**

```text
Error when reading or editing Project Service:
Permission denied to list services for consumer container.
HTTP 403
```

The GitHub Actions service account lacked permission to list or manage enabled project services.

Check the existing IAM roles:

```bash
gcloud projects get-iam-policy civic-champion-439320-a5 \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:github-actions@civic-champion-439320-a5.iam.gserviceaccount.com" \
  --format="table(bindings.role)"
```

Permission granted during troubleshooting:

```bash
gcloud projects add-iam-policy-binding civic-champion-439320-a5 \
  --member="serviceAccount:github-actions@civic-champion-439320-a5.iam.gserviceaccount.com" \
  --role="roles/serviceusage.serviceUsageAdmin"
```

This role permits service/API administration without granting project Owner access.

### IAM Policy Modification Denied

**Error encountered:**

```text
IAM_PERMISSION_DENIED
```

Verify the active Cloud Shell identity:

```bash
gcloud auth list
```

Verify its project roles:

```bash
gcloud projects get-iam-policy civic-champion-439320-a5 \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:abbeyster@gmail.com" \
  --format="table(bindings.role)"
```

Recorded roles:

```text
roles/compute.admin
roles/owner
```

### Artifact Registry Repository Creation

**Missing permission:**

```text
artifactregistry.repositories.create
```

The existing `roles/artifactregistry.writer` role allowed image uploads to an existing repository but did not allow Terraform to create the repository.

Permission granted:

```bash
gcloud projects add-iam-policy-binding civic-champion-439320-a5 \
  --member="serviceAccount:github-actions@civic-champion-439320-a5.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.admin"
```

### GKE Cluster Creation

**Missing permission:**

```text
container.clusters.create
```

Permission granted:

```bash
gcloud projects add-iam-policy-binding civic-champion-439320-a5 \
  --member="serviceAccount:github-actions@civic-champion-439320-a5.iam.gserviceaccount.com" \
  --role="roles/container.admin"
```

### Compute Engine Service Account Access

The deployment identity lacked access to:

```text
1006034492977-compute@developer.gserviceaccount.com
```

The following binding was used:

```bash
gcloud iam service-accounts add-iam-policy-binding \
  1006034492977-compute@developer.gserviceaccount.com \
  --member="serviceAccount:github-actions@civic-champion-439320-a5.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser" \
  --project=civic-champion-439320-a5
```

### Compute Engine Instance Group Permissions

**Missing permission:**

```text
compute.instanceGroupManagers.list
```

Permission granted:

```bash
gcloud projects add-iam-policy-binding civic-champion-439320-a5 \
  --member="serviceAccount:github-actions@civic-champion-439320-a5.iam.gserviceaccount.com" \
  --role="roles/compute.admin"
```

### Verify Final IAM Roles

```bash
gcloud projects get-iam-policy civic-champion-439320-a5 \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:github-actions@civic-champion-439320-a5.iam.gserviceaccount.com" \
  --format="table(bindings.role)"
```

Roles recorded during troubleshooting:

```text
roles/serviceusage.serviceUsageAdmin
roles/artifactregistry.admin
roles/container.admin
roles/compute.admin
```

---

## 3. Terraform Remote State Configuration

### Configure the GCS Backend

The Terraform configuration was updated to use a Google Cloud Storage backend for persistent state management.

From the repository root, inspect the Terraform directory:

```bash
ls terraform/gcp-gke
```

Configure the backend in `terraform/gcp-gke/providers.tf`:

```hcl
terraform {
  backend "gcs" {
    bucket = "civic-champion-439320-a5-terraform-state"
    prefix = "gke"
  }
}
```

### Initialize and Migrate Terraform State

Run from the Terraform working directory:

```bash
terraform init -migrate-state
```

Recorded output:

```text
Initializing the backend...

Successfully configured the backend "gcs"!
Terraform will automatically use this backend unless
the backend configuration changes.

Initializing provider plugins...
- Reusing previous version of hashicorp/google from the dependency lock file
- Using previously-installed hashicorp/google v7.46.1

Terraform has been successfully initialized!
```

The backend initialization succeeded.

### Verify the Remote State

Check for state objects in the GCS bucket:

```bash
gcloud storage ls --recursive \
  gs://civic-champion-439320-a5-terraform-state
```

Inspect resources recorded in Terraform state:

```bash
terraform state list
```

The local state was also inspected:

```bash
terraform show terraform.tfstate
```

**Troubleshooting observation:** The local state was already empty. Successful backend initialization alone did not establish that existing infrastructure resources had been migrated.

### Grant GitHub Actions Access to Terraform State

The GitHub Actions service account required permission to read and write state objects in the GCS bucket.

Permission granted:

```bash
gcloud storage buckets add-iam-policy-binding \
  gs://civic-champion-439320-a5-terraform-state \
  --member="serviceAccount:github-actions@civic-champion-439320-a5.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"
```

---

## 4. Infrastructure Cleanup During Troubleshooting

The following commands were used during troubleshooting and are retained for historical reference.

**Warning:** These are destructive commands. Do not run them against an active deployment without confirming the intended resource removal and Terraform state implications.

### Artifact Registry Repository

List repositories:

```bash
gcloud artifacts repositories list \
  --location=northamerica-northeast2 \
  --project=civic-champion-439320-a5
```

Repository deletion command used during troubleshooting:

```bash
gcloud artifacts repositories delete moodle-repo \
  --location=northamerica-northeast2 \
  --project=civic-champion-439320-a5
```

Recorded result:

```text
Deleted repository [moodle-repo].
```

### GKE Cluster

Cluster deletion command recorded during troubleshooting:

```bash
gcloud container clusters delete moodle-gke-cluster \
  --zone northamerica-northeast2-a \
  --project civic-champion-439320-a5
```

---

## 5. GitHub Actions Deployment Troubleshooting

### MySQL Deployment – Missing Secret Manifest

**Error encountered:**

```text
Deploying MySQL...

error: accumulating resources:
accumulation err='accumulating resources from
secret.yaml':

open /home/runner/work/cloud-infra-single-node/
cloud-infra-single-node/kubernetes/gcp-gke/mysql/secret.yaml:
no such file or directory

error: no objects passed to apply

Error: Process completed with exit code 1.
```

The Kubernetes deployment referenced `secret.yaml`, but the file was unavailable in the GitHub Actions runner.

The file existed locally, so the next investigation was whether Git tracked it.

Run from the repository root:

```bash
git ls-files kubernetes/gcp-gke/mysql/secret.yaml
```

If tracked, the command returns:

```text
kubernetes/gcp-gke/mysql/secret.yaml
```

**Security consideration:** Kubernetes Secret manifests containing actual credentials should not be committed to a public repository. Deployment secrets should be generated or supplied securely through the pipeline.

---

## 6. GKE Managed TLS Certificate Troubleshooting

### Certificate Resource Name Mismatch

The deployed Ingress referenced a managed certificate name that did not match the Kubernetes `ManagedCertificate` resource.

The certificate configuration was inspected using:

```bash
grep -R \
  "kind: ManagedCertificate\|name: moodle-managed-cert\|name: moodle-ssl-cert" \
  kubernetes/gcp-gke
```

Recorded result:

```text
kubernetes/gcp-gke/overlays/managed-cert.yaml:kind: ManagedCertificate
kubernetes/gcp-gke/overlays/managed-cert.yaml:  name: moodle-ssl-cert
```

The actual certificate resource was:

```yaml
name: moodle-ssl-cert
```

However, the deployed Ingress referenced:

```yaml
networking.gke.io/managed-certificates: "moodle-managed-cert"
```

### Locate the Incorrect Reference

Search the Kubernetes manifests and deployment scripts:

```bash
grep -R "moodle-managed-cert" kubernetes scripts
```

Recorded result:

```text
kubernetes/gcp-gke/overlays/ingress.yaml:
  networking.gke.io/managed-certificates: "moodle-managed-cert"
```

### Correct the Ingress Annotation

File:

```text
kubernetes/gcp-gke/overlays/ingress.yaml
```

Original annotation:

```yaml
networking.gke.io/managed-certificates: "moodle-managed-cert"
```

Corrected annotation:

```yaml
networking.gke.io/managed-certificates: "moodle-ssl-cert"
```

---

## 7. Troubleshooting Summary

The Phase 3 GKE CI/CD implementation encountered several configuration and deployment issues:

- Workload Identity Federation and GitHub Actions service account verification
- Missing IAM permissions for project services, Artifact Registry, GKE, and Compute Engine
- Terraform remote state configuration and GCS bucket permissions
- Infrastructure cleanup during Terraform and deployment troubleshooting
- Missing MySQL Secret manifest in the GitHub Actions runner
- Mismatched GKE managed TLS certificate references
