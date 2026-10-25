# Custom Domain and HTTPS – Azure Red Hat OpenShift (ARO)

## Goal

Configure `bordercolliechronicles.ca` to reach the Moodle deployment on Azure Red Hat OpenShift (ARO) over HTTPS, using a custom OpenShift Route with an edge TLS certificate.

## 1. DNS and Initial TLS Issue

The domain was pointed to the ARO ingress public IP:

```text
A     bordercolliechronicles.ca     4.249.190.38
```

Porkbun DNS also contained `_acme-challenge` TXT records used for Let's Encrypt domain validation. The nameservers recorded during setup were:

```text
curitiba.ns.porkbun.com
fortaleza.ns.porkbun.com
maceio.ns.porkbun.com
salvador.ns.porkbun.com
```

Initially, browsers displayed **“Your connection is not private.”** The ARO default Route served `moodle-default.apps.moodle-aro.centralus.aroapp.io`, but the certificate presented for the custom domain did not cover `bordercolliechronicles.ca`. DNS pointing to the cluster alone was not sufficient to establish trusted HTTPS.

## 2. Obtain the Domain Certificate

The certificate files were obtained through the domain's SSL management interface. The Route requires:

- The domain certificate
- Its matching private key
- The certificate chain, when required by the issuing CA

The local files used during configuration were:

```text
ssl/bordercolliechronicles.ca/bordercolliechronicles.ca-ssl-bundle/
├── domain.cert.pem
└── private.key.pem
```

**Security:** Keep the private key outside the public repository. Do not commit certificate private keys or paste their contents into documentation.

### Verify certificate coverage

From Git Bash, with the repository's parent directory containing `ssl/` as the working directory:

```bash
openssl x509 \
  -in ssl/bordercolliechronicles.ca/bordercolliechronicles.ca-ssl-bundle/domain.cert.pem \
  -noout -subject -ext subjectAltName
```

Recorded output:

```text
subject=CN=bordercolliechronicles.ca
X509v3 Subject Alternative Name:
    DNS:*.bordercolliechronicles.ca, DNS:bordercolliechronicles.ca
```

The certificate covered the root domain and wildcard subdomains.

### Verify that the certificate matches the private key

```bash
SSL_DIR="ssl/bordercolliechronicles.ca/bordercolliechronicles.ca-ssl-bundle"

openssl x509 -in "$SSL_DIR/domain.cert.pem" -pubkey -noout | openssl sha256
openssl pkey -in "$SSL_DIR/private.key.pem" -pubout | openssl sha256
```

The two SHA-256 hashes should match. If the certificate issuer provided a separate chain, ensure the certificate file supplied to the Route includes the required chain or configure it appropriately.

## 3. Create the Custom ARO Route

With the `oc` CLI authenticated to the ARO cluster and the `moodle` namespace available:

```bash
SSL_DIR="ssl/bordercolliechronicles.ca/bordercolliechronicles.ca-ssl-bundle"

oc create route edge moodle-custom \
  --service=nginx \
  --hostname=bordercolliechronicles.ca \
  --port=http \
  --cert="$SSL_DIR/domain.cert.pem" \
  --key="$SSL_DIR/private.key.pem" \
  --insecure-policy=Redirect \
  -n moodle
```

Recorded result:

```text
route.route.openshift.io/moodle-custom created
```

This added a custom Route alongside the existing ARO hostname:

- `moodle`: `moodle-default.apps.moodle-aro.centralus.aroapp.io`
- `moodle-custom`: `bordercolliechronicles.ca`

The custom Route terminates TLS at the OpenShift router and redirects HTTP traffic to HTTPS.

---

### Verify Routes

```bash
oc get routes -n moodle
```

Expected entries:

```text
NAME            HOST/PORT                                          SERVICES   PORT   TERMINATION
moodle          moodle-default.apps.moodle-aro.centralus.aroapp.io  nginx      http   edge/Redirect
moodle-custom   bordercolliechronicles.ca                           nginx      http   edge/Redirect
```
---

---

## 4. Verify HTTPS

```bash
curl -Iv https://bordercolliechronicles.ca
```

Check that TLS validation succeeds and the certificate matches the requested domain. The notes record that HTTPS became operational after configuring the custom Route.

---

## 5. Update Moodle's Public URL

Moodle's `config.php` initially referenced the default ARO hostname. Update `$CFG->wwwroot` to the custom HTTPS domain.

The command used during deployment was:

```bash
MSYS_NO_PATHCONV=1 oc exec deployment/php -c php -n moodle -- \
  sed -i 's|https://moodle-default.apps.moodle-aro.centralus.aroapp.io|https://bordercolliechronicles.ca|' /var/www/html/config.php
```

Verify the result:

```bash
MSYS_NO_PATHCONV=1 oc exec deployment/php -c php -n moodle -- \
  grep 'wwwroot' /var/www/html/config.php
```

Expected configuration:

```php
$CFG->wwwroot = 'https://bordercolliechronicles.ca';
```

**Persistence consideration:** The notes record that Moodle was verified after a PHP pod was deleted and recreated. Any future deployment or configuration automation must preserve the custom `$CFG->wwwroot` value, rather than resetting it to the default ARO hostname.

---

## 6. Recreate the Route After Cluster Teardown

After recreating the ARO cluster, re-establish DNS pointing to the new ingress IP if it changed, confirm the certificate is still valid, and recreate the custom Route from the local certificate files:

```bash
SSL_DIR="ssl/bordercolliechronicles.ca/bordercolliechronicles.ca-ssl-bundle"

oc create route edge moodle-custom \
  --service=nginx \
  --hostname=bordercolliechronicles.ca \
  --port=http \
  --cert="$SSL_DIR/domain.cert.pem" \
  --key="$SSL_DIR/private.key.pem" \
  --insecure-policy=Redirect \
  -n moodle

oc get routes -n moodle
```

The `oc create route` command is for a Route that does not yet exist; if it already exists, inspect or update the existing resource instead.

---

## 7. Validation Outcome

The recorded deployment confirmed:

- The domain resolved to the ARO ingress endpoint.
- The certificate covered `bordercolliechronicles.ca` and `*.bordercolliechronicles.ca`.
- The `moodle-custom` edge Route served the custom hostname over HTTPS.
- Moodle's `$CFG->wwwroot` was updated to the custom domain.
- The custom domain remained usable after PHP pod recreation.

**Result:** `https://bordercolliechronicles.ca` was verified working on the ARO deployment at the time of testing. This is a historical validation result, not a claim about the domain's current availability.
