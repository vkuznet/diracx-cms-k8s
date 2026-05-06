# diracx-cms Helm Chart

Packages the full DiracX stack for CMS deployments:

| Component | Bundled? | Disable with |
|---|---|---|
| DiracX API | always | – |
| DiracX Web UI | always | – |
| Dex (OIDC) | always | – |
| MySQL | optional | `mysql.enabled: false` |
| OpenSearch | optional | `opensearch.enabled: false` |
| MinIO (S3) | optional | `minio.enabled: false` |

cert-manager is **not** bundled — it must be installed separately (see below).

---

## Prerequisites

### 1 – Install cert-manager (once per cluster)

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --wait
```

Verify:
```bash
kubectl get pods -n cert-manager
# cert-manager-*, cert-manager-cainjector-*, cert-manager-webhook-* → Running
```

### 2 – ingress-nginx (once per cluster, if not already present)

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace --wait
```

---

## Deploying DiracX on a new cluster

### Minimal override file

Create `values-<clustername>.yaml`:

```yaml
global:
  namespace: diracx-cms
  hostname: cms-diracx-test20     # change per cluster
  releaseName: diracx-cms         # change if you want a different k8s prefix
  storageClass: cinder-standard-delete # change if necessary
  storageClassRWX: manila-meyrin-cephfs # change if necessary
```

That is all that is required to target a new cluster.

For example, when you use local k8s cluster, e.g. running docker desktop
with kind cluster, you may use the following values:

```yaml
global:
  namespace: diracx-cms
  hostname: localhost
  releaseName: diracx-cms
  storageClass: hostpath
  storageClassRWX: hostpath
```

If you are unware which storage class is available to you just use the
following command:

```bash
kubectl get storageclass
```

### Install

```bash
# step 1: create your values-my.yaml file
# here is the one I use on local k8s cluster
cat values-my.yaml

global:
  namespace: diracx-cms
  hostname: localhost
  releaseName: diracx-cms
  storageClass: hostpath
  storageClassRWX: hostpath

# install helm chart
helm install diracx-cms ./helm/diracx-cms \
  -f values-my.yaml \
  --namespace default --create-namespace \
  --wait
```

### Upgrade after config change

```bash
helm upgrade diracx-cms ./helm/diracx-cms \
  -f values-cms-diracx-test20.yaml \
  --namespace default
```

### Uninstall

```bash
helm uninstall diracx-cms --namespace default
```

> **Note:** PVCs are not deleted by `helm uninstall`. Delete them manually if you
> want a full teardown:
> ```bash
> kubectl delete pvc -l app.kubernetes.io/instance=diracx-cms -n default
> ```

---

## Using external MySQL / OpenSearch / MinIO

Disable the bundled service and supply connection details:

```yaml
mysql:
  enabled: false

external:
  mysql:
    host: my-mysql.example.com
    port: 3306
    appUser: sqldiracx
    appPassword: "s3cr3t"
    rootUser: root
    rootPassword: "r00t"
```

```yaml
opensearch:
  enabled: false

external:
  opensearch:
    host: my-opensearch.example.com
    port: 9200
    user: admin
    password: "adm1n"
```

```yaml
minio:
  enabled: false

external:
  minio:
    endpointUrl: "https://s3.example.com"
    accessKeyId: "AKID..."
    secretAccessKey: "wJalr..."
```

---

## Deploying on multiple clusters simultaneously

Each cluster needs its own override file.  Use `global.releaseName` to avoid
k8s object name collisions when both clusters share a namespace:

| File | hostname | releaseName |
|---|---|---|
| `values-test18.yaml` | `cms-diracx-test18` | `diracx-cms` |
| `values-test20.yaml` | `cms-diracx-test20` | `diracx-test20` |

```bash
# cluster test18
helm install diracx-cms ./helm/diracx-cms -f values-test18.yaml

# cluster test20 (different context)
kubectl config use-context cmsweb-test20
helm install diracx-test20 ./helm/diracx-cms -f values-test20.yaml
```

---

## Init Job execution order

The Helm `post-install` hooks run jobs in weight order after all resources are created:

| Weight | Job | Purpose |
|---|---|---|
| 1 | `init-secrets` | Generate MySQL/MinIO passwords, SQL/OS DSN secrets, auth state key |
| 2 | `init-sql` | Create MySQL databases and tables |
| 3 | `init-os` | Create OpenSearch indices |
| 4 | `init-keystore` | Generate JWKS signing key, store as `diracx-jwks` secret |
| 5 | `init-cs` | Seed configuration store git repo on `pvc-cs-store` |

To **re-run** a job after a failure:
```bash
kubectl delete job diracx-cms-init-sql -n default
helm upgrade diracx-cms ./helm/diracx-cms -f values-test18.yaml
```

---

## cert-manager integration

The chart creates:
1. `selfsigned-issuer` — bootstrap Issuer (self-signed)
2. `diracx-selfsigned-ca` — CA Certificate stored in `root-secret`
3. `diracx-ca-issuer` — CA-backed Issuer for signing the Ingress TLS cert
4. `diracx-cms-ingress-tls` — Certificate for `global.hostname`, stored in `myingress-cert`

These are controlled by:
```yaml
certManager:
  issuerName: diracx-ca-issuer
  issuerKind: Issuer          # or ClusterIssuer for a shared CA
  caCertName: diracx-selfsigned-ca
  caSecretName: root-secret
```

If your cluster already has a CA issuer, point `certManager.issuerName` at it
and set `certManager.issuerKind: ClusterIssuer`.

---

## Key values reference

| Value | Default | Description |
|---|---|---|
| `global.hostname` | `cms-diracx-test18` | Public hostname – **change per cluster** |
| `global.releaseName` | `diracx-cms` | Prefix for all k8s object names |
| `global.namespace` | `default` | Target namespace |
| `global.storageClass` | `cinder-standard-delete` | RWO storage class |
| `global.storageClassRWX` | `manila-meyrin-cephfs` | RWX storage class |
| `mysql.enabled` | `true` | Deploy bundled MySQL |
| `opensearch.enabled` | `true` | Deploy bundled OpenSearch |
| `minio.enabled` | `true` | Deploy bundled MinIO |
| `dex.nodePort` | `32002` | NodePort for Dex OIDC |
| `minio.nodePort` | `32000` | NodePort for MinIO S3 |
| `minio.consoleNodePort` | `32001` | NodePort for MinIO console |
