# Phase 4 – Red Hat OpenShift Developer Sandbox Deployment

## Goal

Deploy the Moodle architecture proven on GKE to the Red Hat OpenShift Developer Sandbox while preserving separate Nginx, PHP-FPM 8.2, and MySQL 8.0 workloads, an application initialization container, and persistent application and database storage. Adapt the workloads to OpenShift's restricted security context, internal image registry, and Route-based HTTPS access.

## Prerequisites

- Access to a Red Hat OpenShift Developer Sandbox project and the OpenShift web console.
- `oc`, Git Bash, and the project repository checked out locally.
- Run the commands below from the root of `multi-platform-moodle-infra` unless stated otherwise.
- The project-specific Kubernetes manifests under `kubernetes/openshift/` and configuration script `scripts/configure-moodle-openshift.sh`.

Set OPENSHIFT_NAMESPACE to your current OpenShift Sandbox project before deployment. Obtain a fresh login token if your previous session has expired.

---

## 1. Log in and select the project

In the OpenShift console, open the user menu, select **Copy login command**, and, if requested, **Display Token**. Run the supplied `oc login` command in Git Bash. Keep the token private.

```bash
oc whoami
oc project
```

Select the project used for this deployment:

```bash
OPENSHIFT_NAMESPACE="dolliebears-dev"
oc project "$OPENSHIFT_NAMESPACE"
```
---

## 2. Create application secrets

Read passwords without echoing them to the terminal:

```bash
read -rsp "Enter MySQL root password: " MYSQL_ROOT_PASSWORD
echo
read -rsp "Enter Moodle database password: " DB_PASSWORD
echo
read -rsp "Enter Moodle admin password: " MOODLE_ADMIN_PASSWORD
echo
```

Create the secrets used by the application:

```bash
oc create secret generic moodle-admin-secret \
  --from-literal=admin-password="$MOODLE_ADMIN_PASSWORD"

oc create secret generic mysql-secret \
  --from-literal=root-password="$MYSQL_ROOT_PASSWORD" \
  --from-literal=mysql-database=moodle \
  --from-literal=mysql-user=moodleuser \
  --from-literal=moodleuser-password="$DB_PASSWORD"

oc create secret generic php-secret \
  --from-literal=db-password="$DB_PASSWORD"

unset MYSQL_ROOT_PASSWORD DB_PASSWORD MOODLE_ADMIN_PASSWORD
```

Verify the secret names without printing their values:

```bash
oc get secret mysql-secret php-secret moodle-admin-secret
```
---

## 3. Build the PHP-FPM image in OpenShift

The PHP-FPM image uses the existing Docker build context under `docker/php/`. Create an ImageStream and binary Docker build that publishes directly to tag `8.2`:

```bash
oc create imagestream custom-php

oc new-build \
  --name=custom-php \
  --strategy=docker \
  --binary=true \
  --to=custom-php:8.2

oc start-build custom-php \
  --from-dir=docker/php \
  --follow
```
---

## 4. Build the Moodle initialization image

The OpenShift-specific initialization image includes required tools in the image rather than installing packages at container startup. This accommodates the restricted, non-root security context.

```bash
oc create imagestream moodle-init

oc new-build \
  --name=moodle-init \
  --strategy=docker \
  --binary=true \
  --to=moodle-init:8.2

oc start-build moodle-init \
  --from-dir=kubernetes/openshift/images/moodle-init \
  --follow
```

Verify both image tags:

```bash
oc get imagestream custom-php moodle-init
```

The PHP deployment must reference the images in the **current** OpenShift namespace. Its PHP container uses `custom-php:8.2`; its `init-moodle` container uses `moodle-init:8.2`.

---

## 5. OpenShift security and Nginx configuration

The application runs under OpenShift's restricted security constraints rather than relying on root access or hard-coded ownership changes. The initialization image must not run `apk add` at startup, and mounted-volume access must be compatible with the assigned security context and `fsGroup`.

The Nginx deployment must use an image/configuration compatible with an arbitrary non-root UID and listen on an unprivileged port. The troubleshooting notes record adapting Nginx to port `8080` while keeping the Service port at `80`:

```yaml
# Nginx container and readiness probe
containerPort: 8080
readinessProbe:
  httpGet:
    path: /healthz
    port: 8080
```

```nginx
listen 8080;
```

```yaml
# Nginx Service
ports:
  - port: 80
    targetPort: 8080
```

The notes mention both a Red Hat UBI Nginx image and `nginxinc/nginx-unprivileged:stable` during different iterations. Use the image configured in the final repository manifests; the source notes do not establish which one was the final deployed image.

Render the manifests to check the effective configuration before applying them:

```bash
oc kustomize kubernetes/openshift/nginx
oc kustomize kubernetes/openshift/overlays
```
---

## 6. Deploy persistent storage and workloads

Apply the Kustomize directories in deployment order:

```bash
# Persistent volumes and claims
oc apply -k kubernetes/openshift/storage
oc get pvc

# MySQL
oc apply -k kubernetes/openshift/mysql
oc get pods

# PHP-FPM and Moodle init container
oc apply -k kubernetes/openshift/php
oc get pods

# Nginx
oc apply -k kubernetes/openshift/nginx
oc get pods

# OpenShift Route
oc apply -k kubernetes/openshift/overlays
oc get routes
```

The PHP deployment references a dedicated `moodle-openshift-sa` service account. Ensure that account is present in the selected namespace before the PHP deployment creates pods:

```bash
oc get serviceaccount moodle-openshift-sa
```

If it is absent, apply the repository manifest that defines the account before continuing; the supplied notes do not identify that manifest's exact filename.

---

## 7. Configure Moodle

Run the repository configuration script:

```bash
bash ./scripts/configure-moodle-openshift.sh
```

Verify workload readiness and storage:

```bash
oc get pods
oc get deployments
oc get services
oc get pvc
oc get routes
```

Confirm the Route responds over HTTPS using the hostname returned by `oc get routes`:

```bash
curl -I "https://<openshift-route-hostname>"
```

If Moodle's URL or reverse-proxy configuration needs inspection, check `config.php` in the PHP container:

```bash
MSYS_NO_PATHCONV=1 oc exec deployment/php -c php -- \
  grep -E 'wwwroot|getremoteaddrconf|sslproxy' /var/www/html/config.php
```

The configured `$CFG->wwwroot` must match the HTTPS Route hostname, and SSL termination at the OpenShift router requires appropriate reverse-proxy settings.

---

## 8. Validate persistence and application functionality

1. Sign in to Moodle as the administrator and complete the administrator profile.
2. Upload a profile image and verify that it displays.
3. Create a test course (recorded as **Infrastructure Test Course**) and upload a course image.
4. Confirm both images display before restarting the application workload.
5. Delete the running PHP pod, allowing the Deployment to recreate it:

```bash
oc get pods
oc delete pod <current-php-pod-name>
oc get pods
```

6. Sign in again and confirm the administrator profile image and test course remain available.

---

## 9. Additional validation

Inspect the assigned security context and relevant events if a workload fails to start:

```bash
oc describe deployment php
oc get pods
oc get events --sort-by=.lastTimestamp
```

The troubleshooting record also includes a successful PHP-to-MySQL connection test from the PHP container, confirming connectivity between the application runtime and database.

For failures involving the service account, init-container package installation, Nginx security restrictions, image tags, or route/HTTPS settings, refer to `p4_post_mortem.md`.
