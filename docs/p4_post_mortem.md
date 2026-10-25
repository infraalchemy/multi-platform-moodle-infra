# OpenShift Deployment Post-Mortem

Adapting the Moodle deployment from GKE to the Red Hat OpenShift Developer Sandbox exposed differences in namespace-scoped resources, image builds, container security, and application routing. This document records the problems, causes, and fixes documented during Phase 4 while preserving the existing Nginx, PHP-FPM, MySQL, and persistent-storage architecture.

## 1. PHP Deployment Blocked by Missing ServiceAccount

* **The Problem:** The PHP deployment reported `ReplicaFailure=True` and `FailedCreate`, with no application pod created.
* **The Cause:** The pod specification referenced `moodle-openshift-sa`, but that ServiceAccount did not exist in the active OpenShift project. The ReplicaSet reported `serviceaccount "moodle-openshift-sa" not found`.
* **The Fix:** Created the required ServiceAccount in the deployment namespace before retrying the PHP deployment. Verified the ServiceAccount and inspected the ReplicaSet events to confirm the cause of the failure.

```bash
oc project
oc get serviceaccount moodle-openshift-sa
oc describe rs php-6c689ffb45

# Run only if the ServiceAccount is missing and is not already created by the manifests.
oc create serviceaccount moodle-openshift-sa

oc apply -k kubernetes/openshift/php
oc get pods
```

The subsequent pod progressed to the init-container stage, confirming that the missing ServiceAccount had been a separate deployment blocker.

---

## 2. Moodle Init Container Failed Under OpenShift Security Restrictions

* **The Problem:** The PHP pod entered `Init:Error` while preparing the Moodle application files.
* **The Cause:** The init container attempted to install packages using `apk` at runtime. OpenShift's `restricted-v2` Security Context Constraint (SCC) ran the container without the privileges required to modify the package database.
* **The Fix:** Created a dedicated OpenShift-compatible `moodle-init` image with `wget` and `tar` installed at image-build time. Removed runtime package installation and hard-coded `33:33` ownership changes, allowing the init container to operate under the assigned security context.

Recorded error:

```text
Installing init-container tools...
ERROR: Unable to lock database: Permission denied
ERROR: Failed to open apk database: Permission denied
```

Build the replacement init image from the repository root:

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

The PHP init-container image reference was updated to use the OpenShift internal registry and `moodle-init:8.2` tag.

---

## 3. Persistent Volume Access with Arbitrary Non-Root UIDs

* **The Problem:** The GKE initialization approach assumed fixed container ownership and raised concerns about whether Moodle application files and `moodledata` would remain writable under OpenShift's non-root execution model.
* **The Cause:** OpenShift assigned the pod a security context rather than relying on the fixed user/group assumptions used in the earlier deployment.
* **The Fix:** Removed hard-coded ownership operations and used the OpenShift-assigned `fsGroup` for access to supported mounted volumes. Verified that both application and data volumes were mounted read/write.

Recorded security context and mount checks:

```text
SCC:      restricted-v2
fsGroup:  1004430000

/var/www/html   rw
/moodledata     rw
```

This preserved the application's persistent-storage design without relaxing the OpenShift SCC.

---

## 4. PHP Image Build Output Used the Wrong Tag

* **The Problem:** The initial OpenShift binary build published `custom-php:latest`, while the PHP deployment expected `custom-php:8.2`.
* **The Cause:** The initial BuildConfig used its default `latest` output tag.
* **The Fix:** Tagged the existing image as `8.2`, updated the BuildConfig to publish directly to that tag, and removed the unnecessary `latest` tag. Subsequent builds specified the intended tag from the start.

```bash
oc tag custom-php:latest custom-php:8.2

oc patch bc custom-php \
  -p '{"spec":{"output":{"to":{"kind":"ImageStreamTag","name":"custom-php:8.2"}}}}'

oc get bc custom-php -o jsonpath='{.spec.output.to.name}{"\n"}'
oc tag -d custom-php:latest
oc get imagestream custom-php
```

The resulting deployment image references used the internal registry path for the active project rather than a hard-coded path from an earlier Sandbox namespace.

---

## 5. Nginx Configuration Incompatible with Restricted Execution

* **The Problem:** The Nginx configuration carried forward from GKE required changes to run within OpenShift's non-root security restrictions.
* **The Cause:** The initial configuration used the standard `nginx:stable` image and port 80 assumptions that did not align with the restricted container environment.
* **The Fix:** The troubleshooting notes document switching to an OpenShift-compatible Nginx image and listening on port 8080, while preserving port 80 on the Kubernetes Service. The readiness probe was also updated to target the container's new port.

Recorded image change:

```yaml
image: registry.access.redhat.com/ubi9/nginx-126
```

Recorded port and readiness configuration:

```nginx
listen 8080;
```

```yaml
# Deployment container port
containerPort: 8080

# Service port mapping
ports:
  - port: 80
    targetPort: 8080

# Readiness probe
readinessProbe:
  httpGet:
    path: /healthz
    port: 8080
```

The notes also later identify `nginxinc/nginx-unprivileged:stable` as the image used for the deployment. The troubleshooting record therefore documents both image references; the repository manifests should be treated as the source of truth for the final deployed image.

---

## 6. Moodle Route and HTTPS Configuration

* **The Problem:** The notes record an HTTPS troubleshooting path for cases where the Moodle page did not render correctly behind the OpenShift Route.
* **The Cause:** The application URL and reverse-proxy settings needed to reflect TLS termination at the OpenShift router rather than an HTTP endpoint inside the cluster.
* **The Fix:** Corrected Moodle's `wwwroot` to use the HTTPS Route hostname and enabled `sslproxy` in `config.php`. Verified the resulting configuration and tested the Route over HTTPS.

Recorded checks and changes (use the current Route hostname rather than reusing an expired Sandbox hostname):

```bash
oc get route moodle

MSYS_NO_PATHCONV=1 oc exec deployment/php -c php -- \
  grep -E 'wwwroot|getremoteaddrconf|sslproxy' /var/www/html/config.php
```

The original notes also show changing the recorded Sandbox URL from HTTP to HTTPS and inserting:

```php
$CFG->sslproxy = 1;
```

These commands were documented as troubleshooting steps; the supplied record does not independently establish that every HTTPS symptom occurred in the final deployment.

---

## 7. Validation of Application Connectivity and Persistence

Following the security and deployment adjustments, the troubleshooting notes record a successful PHP-to-MySQL connection test:

```text
PHP -> MySQL connection successful
```

Application persistence was tested by creating a Moodle administrator profile image and a test course with an uploaded image, deleting the PHP pod, and confirming that the content remained available after Kubernetes recreated the pod.

The notes also record an HTTPS request to the OpenShift Route:

```bash
curl -I https://moodle-dolliebears-dev.apps.rm3.7wse.p1.openshiftapps.com
```

Together, these checks covered service connectivity, application data persistence, workload recreation, and external routing. 
