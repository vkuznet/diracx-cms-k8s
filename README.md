# DiracX Kubernetes Manifests

This repository contains extracted Kubernetes manifests from a running DiracX demo cluster,
organized for manual installation on an **external** (non-kind) Kubernetes cluster.

## Directory Structure

```
diracx-k8s/
├── crds/               # CustomResourceDefinitions (cert-manager)
├── namespaces/         # Namespace definitions
├── rbac/               # ServiceAccounts, Roles, RoleBindings
├── configmaps/         # ConfigMaps
├── secrets/            # Secrets (⚠ contain real credentials – see notes)
├── pvcs/               # PersistentVolumeClaims
├── deployments/        # Deployments
├── statefulsets/       # StatefulSets (MySQL, OpenSearch)
├── services/           # Services
├── ingress/            # Ingress resources
├── jobs/               # One-time init Jobs
├── cronjobs/           # Scheduled Jobs
└── helm/               # Helm chart stub (empty, ready to populate)
    └── diracx/
        ├── Chart.yaml
        ├── values.yaml
        └── templates/
```

---

## Pre-requisites

- `kubectl` configured against your target cluster
- A running ingress-nginx controller (see Step 0)
- A `StorageClass` that can fulfil `ReadWriteOnce` (most clusters: `standard`, `gp2`, etc.)
- A `StorageClass` that can fulfil `ReadWriteMany` for `pvc-cs-store`
  (e.g. NFS-backed, CephFS, AWS EFS, etc.)

### Before You Begin – Adapt Hostnames

Several resources contain the original hostname **`cms-diracx-test18.cern.ch`**.
Search-and-replace it with your actual external hostname or IP:

```bash
HOSTNAME=your.cluster.hostname.or.ip
grep -rl 'cms-diracx-test18.cern.ch' . | xargs sed -i "s/cms-diracx-test18.cern.ch/${HOSTNAME}/g"
```

Resources affected:
- `ingress/diracx-cms.yaml`          – `spec.rules[].host` and `spec.tls[].hosts[]`
- `secrets/diracx-secrets.yaml`       – `DIRACX_SANDBOX_STORE_S3_CLIENT_KWARGS`,
                                         `DIRACX_SERVICE_AUTH_ALLOWED_REDIRECTS`,
                                         `DIRACX_SERVICE_AUTH_TOKEN_ISSUER`

### StorageClass Names

The PVCs were extracted from a kind cluster that used the `standard` storage class.
If your cluster uses a different name, edit the relevant files:

```bash
# list your storage classes
kubectl get storageclass

# at CERN k8s cluster we most likely to use either
# cinder-standard or cinder-standard-delete class

# replace 'cinder-standard-delete' with your actual class name
grep -rl 'storageClassName: cinder-standard-delete' pvcs/ | xargs sed -i 's/storageClassName: standard/storageClassName: YOUR_CLASS/g'
```

`pvc-cs-store` needs `ReadWriteMany` – if your storage class only supports `ReadWriteOnce`,
substitute with an RWX-capable one (NFS, CephFS, EFS CSI, etc.).

---

## Step-by-Step Installation

### Step 0 – Install ingress-nginx (if not already present)

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

# Wait for it to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s
```

### Step 1 – Apply CRDs (cert-manager)

CRDs must exist before any resource that references them.

```bash
kubectl apply -f crds/
```

Wait for cert-manager CRDs to be established:

```bash
kubectl wait --for=condition=Established crd \
  certificates.cert-manager.io \
  certificaterequests.cert-manager.io \
  issuers.cert-manager.io \
  clusterissuers.cert-manager.io \
  --timeout=60s
```

### Step 2 – Create Namespace and service accounts

```bash
kubectl apply -f namespaces/
```

Also we need to create several service accounts:
```bash
kubectl create serviceaccount diracx-cms-dex -n default
kubectl create serviceaccount diracx-cms-mysql -n default
kubectl create serviceaccount diracx-cms -n default
kubectl create serviceaccount minio-sa -n default
```


### Step 3 – Apply RBAC

ServiceAccounts, Roles, and RoleBindings must be present before the workloads that reference them.

```bash
kubectl apply -f rbac/
```

### Step 4 – Apply ConfigMaps

```bash
kubectl apply -f configmaps/
```

### Step 5 – Apply Secrets

> **Security note**: The secrets in this directory were exported from a demo cluster and
> contain real (but demo-only) credentials such as MySQL passwords, MinIO root credentials,
> and TLS private keys.  
> **Manifest files**: in secrets manifest files we use base64 encoded strings
> for all values, therefore to see actual values you need to decode them using
> this command: `echo ... | base64 -d`
> Before applying to a production cluster you should:
> 1. Regenerate all passwords/keys
> 2. Consider using a secrets manager (Vault, AWS Secrets Manager, Sealed Secrets, etc.)
> 3. Remove the secrets directory from your git repository or use git-crypt / SOPS

Key secrets and what they contain:

| Secret | Contents |
|---|---|
| `mysql-secret` | MySQL root, replication, and application passwords |
| `diracx-cms-minio` | MinIO root user/password |
| `diracx-secrets` | DiracX runtime configuration (URLs, token settings) |
| `diracx-sql-connection-urls` | MySQL DSNs for each DiracX database |
| `diracx-sql-root-connection-urls` | MySQL root DSNs (used only by init jobs) |
| `diracx-os-connection-urls` | OpenSearch DSNs |
| `diracx-os-root-connection-urls` | OpenSearch root DSNs |
| `diracx-jwks` | JWT signing keys |
| `diracx-dynamic-secrets` | Auth state signing key |
| `root-secret` | TLS certificate authority (CA cert + key) |
| `myingress-cert` | TLS cert for the ingress (signed by root-secret CA) |
| `diracx-cms-cert-manager-webhook-ca` | cert-manager webhook CA |
| `diracx-cms-dex` | Dex OIDC provider config |

```bash
kubectl apply -f secrets/
```

### Step 6 – Create PersistentVolumeClaims

```bash
kubectl apply -f pvcs/
```

Verify they are bound before proceeding:

```bash
kubectl get pvc -n default
# All should show STATUS=Bound before continuing
```

> **Note**: `pvc-diracx-code` was created in the demo cluster with an empty `storageClassName`
> (bound to a kind host-path volume).  On an external cluster you may want to remove this
> PVC and adjust the `diracx-cms-cli` deployment's volume spec to point at a real volume
> containing the DiracX source code, or remove the volume mount entirely if you are running
> the pre-built container image without live source.

### Step 7 – Deploy StatefulSets (MySQL + OpenSearch)

These must come up before the init jobs run.

```bash
# if necessary delete previous statefulsets, e.g.
kubectl delete statefulset diracx-cms-mysql

# apply new one
kubectl apply -f statefulsets/
```

Wait for them to be ready:

```bash
kubectl rollout status statefulset/diracx-cms-mysql -n default --timeout=300s
kubectl rollout status statefulset/opensearch-cluster-master -n default --timeout=300s
```

### Step 8 – Run Init Jobs

The init jobs bootstrap the databases, create the CA/keystore, and seed the configuration
store. They must run in order because each one depends on the previous one completing
successfully.

```bash
# if any of the jobs/pods will require debugging you can use
kubectl apply -f debug/busybox-shell.yaml
# and after that log into its container, e.g.
kubectl exec -it mysql-debug-shell -- sh
# and execute any commands, e.g. probe mysql
$ nc -vz diracx-cms-mysql 3306

# 0. Clone diracx codebase to PVC
# it will run a job with git clone command and copy cloned
# diracx codebase to existing PVC
kubectl apply -f jobs/diracx-cms-code-loader.yaml

# 1. Issue TLS certificates
kubectl apply -f jobs/diracx-cms-issuer-1.yaml
kubectl wait --for=condition=complete job/diracx-cms-issuer-1 --timeout=120s

# 2. Initialize secrets (populates diracx-dynamic-secrets, diracx-jwks)
kubectl apply -f jobs/diracx-cms-init-secrets.yaml
kubectl wait --for=condition=complete job/diracx-cms-init-secrets --timeout=120s
kubectl logs -l app.kubernetes.io/component=init-secrets

# 3. Initialize SQL databases
kubectl apply -f jobs/diracx-cms-init-sql.yaml
kubectl wait --for=condition=complete job/diracx-cms-init-sql --timeout=120s

# 4. Initialize OpenSearch indices
kubectl apply -f jobs/diracx-cms-init-os.yaml
kubectl wait --for=condition=complete job/diracx-cms-init-os --timeout=120s

# 5. Initialize JWKS keystore
kubectl apply -f jobs/diracx-cms-init-keystore.yaml
kubectl wait --for=condition=complete job/diracx-cms-init-keystore --timeout=120s

# 6. Initialize configuration store (git repo on pvc-cs-store)
kubectl apply -f jobs/diracx-cms-init-cs.yaml
kubectl wait --for=condition=complete job/diracx-cms-init-cs --timeout=120s
```

> **Re-running init jobs**: If you need to re-run a job (e.g., after fixing a config error),
> delete it first: `kubectl delete job <name>` then re-apply.

### Step 9. - Install cert-manager via helm
```
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true

kubectl apply -f certs/issuer.yaml
kubectl apply -f certs/ca-cert.yaml
kubectl get secret root-secret
kubectl describe secret root-secret
kubectl apply -f certs/ca-issuer.yaml
kubectl apply -f certs/tls-cert.yaml
kubectl get certificate
kubectl describe certificate diracx-tls
kubectl get secret diracx-tls-secret
kubectl get certificaterequests
kubectl get issuer,certificate

```

### Step 10 – Deploy Dex (OIDC Provider)

```bash
kubectl apply -f deployments/diracx-cms-dex.yaml
kubectl rollout status deployment/diracx-cms-dex -n default --timeout=120s
```

### Step 11 – Deploy MinIO (S3-compatible sandbox storage)

```bash
kubectl apply -f deployments/diracx-cms-minio.yaml
kubectl rollout status deployment/diracx-cms-minio -n default --timeout=120s
```

### Step 12 – Deploy DiracX API + Web + CLI

```bash
kubectl apply -f deployments/diracx-cms.yaml
kubectl apply -f deployments/diracx-cms-web.yaml
kubectl apply -f deployments/diracx-cms-cli.yaml

kubectl rollout status deployment/diracx-cms -n default --timeout=300s
kubectl rollout status deployment/diracx-cms-web -n default --timeout=120s
kubectl rollout status deployment/diracx-cms-cli -n default --timeout=120s
```

### Step 13 – Apply Services

```bash
kubectl apply -f services/
```

### Step 14 – Apply Ingress

Make sure you have replaced `cms-diracx-test18.cern.ch` with your hostname (see Pre-requisites above), then:

```bash
kubectl apply -f ingress/
```

### Step 15 – Apply CronJobs

```bash
kubectl apply -f cronjobs/
```

---

## Post-installation – Seed the Configuration Store

After all pods are running, seed the initial Virtual Organisation and admin user.
Adjust `--vo`, `--idp-url`, `--idp-client-id`, `--preferred-username`, and `--sub` as needed.

```bash
# Get the Dex client UUID from the Dex secret
DEX_CLIENT_ID=$(kubectl get secret diracx-cms-dex -o jsonpath='{.data.config\.yaml}' | base64 -d | grep 'id:' | head -1 | awk '{print $2}')

# Add a Virtual Organisation
kubectl exec deployments/diracx-cms-cli -- bash /entrypoint.sh dirac internal add-vo /cs_store/initialRepo \
  --vo="diracAdmin" \
  --idp-url="https://${HOSTNAME}:32002" \
  --idp-client-id="${DEX_CLIENT_ID}" \
  --default-group="admin"

# Add an admin user (generate a sub with: uuidgen | xargs -I{} sh -c 'printf "\n\$%s\x12\x05local" "{}" | base64 -w 0')
kubectl exec deployments/diracx-cms-cli -- bash /entrypoint.sh dirac internal add-user /cs_store/initialRepo \
  --vo="diracAdmin" \
  --sub="YOUR_DEX_ADMIN_SUB" \
  --preferred-username="admin" \
  --group="admin"
```

---

## Services and Ports

| Service | Type | Port | Notes |
|---|---|---|---|
| diracx-cms | ClusterIP | 8000 | DiracX REST API, fronted by ingress |
| diracx-cms-web | ClusterIP | 8080 | DiracX Web UI, fronted by ingress |
| diracx-cms-dex | NodePort | 32002 | Dex OIDC – must be reachable by browser |
| diracx-cms-minio | NodePort | 32000 | MinIO S3 endpoint |
| diracx-cms-minio-console | NodePort | 32001 | MinIO web console |
| diracx-cms-mysql | ClusterIP | 3306 | MySQL (internal) |
| diracx-cms-mysql-headless | ClusterIP/None | 3306 | MySQL headless for StatefulSet DNS |
| opensearch-cluster-master | ClusterIP | 9200/9300 | OpenSearch (internal) |
| diracx-cms-cert-manager | ClusterIP | 9402 | cert-manager metrics |
| diracx-cms-cert-manager-webhook | ClusterIP | 443 | cert-manager webhook |

---

## What's Not Included / Known Gaps

1. **ClusterRoles / ClusterRoleBindings**: The export only covered the `default` namespace.
   cert-manager likely has cluster-scoped RBAC. Extract with:
   ```bash
   kubectl get clusterrole,clusterrolebinding -l app.kubernetes.io/instance=diracx-cms -o yaml > cluster-rbac.yaml
   ```

2. **PersistentVolumes**: PVs are cluster-scoped and dynamically provisioned.
   On your target cluster the StorageClass will create them automatically when PVCs are applied.

3. **ingress-nginx controller**: Deployed via the upstream manifest in Step 0, not included here.

4. **OpenTelemetry / Grafana**: The demo supports optional telemetry. Those manifests are
   not present in the export because they were not enabled. Enable with `--enable-open-telemetry`
   in the original demo script if you want to export them too.

5. **`pvc-diracx-code`**: In the demo this is a kind host-path volume with the DiracX Python
   source mounted for live development. On an external cluster you likely don't need this.

---

## Regenerating Secrets for Production

The following secrets must be regenerated before any production use:

```bash
# MySQL passwords
MYSQL_ROOT_PW=$(openssl rand -base64 24)
MYSQL_APP_PW=$(openssl rand -base64 24)
MYSQL_REPL_PW=$(openssl rand -base64 24)

kubectl create secret generic mysql-secret \
  --from-literal=mysql-root-password="${MYSQL_ROOT_PW}" \
  --from-literal=mysql-password="${MYSQL_APP_PW}" \
  --from-literal=mysql-replication-password="${MYSQL_REPL_PW}" \
  --dry-run=client -o yaml > secrets/mysql-secret.yaml

# MinIO credentials
kubectl create secret generic diracx-cms-minio \
  --from-literal=rootUser="$(openssl rand -hex 8)" \
  --from-literal=rootPassword="$(openssl rand -base64 18)" \
  --dry-run=client -o yaml > secrets/diracx-cms-minio.yaml

# DiracX auth state key
kubectl create secret generic diracx-dynamic-secrets \
  --from-literal=DIRACX_SERVICE_AUTH_STATE_KEY="$(openssl rand -hex 32)" \
  --dry-run=client -o yaml > secrets/diracx-dynamic-secrets.yaml
```

TLS secrets (`root-secret`, `myingress-cert`, `diracx-cms-cert-manager-webhook-ca`) should be
regenerated by your CA or cert-manager itself once the issuer is configured.

---

## Helm Chart (Future)

The `helm/diracx/` directory is a skeleton ready for you to populate by converting the
raw manifests into parameterized templates. The upstream DiracX Helm chart lives at
[github.com/DIRACGrid/diracx-charts](https://github.com/DIRACGrid/diracx-charts) and is
the recommended path for production deployments.
