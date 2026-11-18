# Qry on Google Cloud Marketplace

[Qry](https://qry.dev) lets people ask their data in plain language, governed by
the permissions the data already has. This repository holds what the Google
Cloud Marketplace listing installs: the Helm chart with the Marketplace's
settings, so the same installation can be made from the command line.

The full guide - what the installation asks for and sets up, the first
administrator, the license, backups, updates, scaling and uninstalling - is at
[docs.qry.dev](https://docs.qry.dev/docs/admin-guide/operations/google-cloud-marketplace).

## Installing from the command line

You need `gcloud`, `kubectl`, `helm` 3 and `openssl`, and a GKE cluster that
enforces network policies (Dataplane V2).

**GKE Autopilot clusters install this way.** The listing's *Click to deploy*
form shows Autopilot clusters as ineligible ("Autopilot cluster integration with
marketplace is in progress"). That is Google's, for every Kubernetes app in the
Marketplace; Qry itself runs on Autopilot. Choose **Deploy via command line**
and follow the steps below.

```bash
gcloud container clusters get-credentials CLUSTER --region REGION
# Google's Application resource, once per cluster:
kubectl apply -f "https://raw.githubusercontent.com/GoogleCloudPlatform/marketplace-k8s-app-tools/master/crd/app-crd.yaml"

export APP_INSTANCE_NAME=qry
export NAMESPACE=qry
export TAG=0.210.3                              # this repository's version (set at each release)
export REGISTRY=marketplace.gcr.io/ixen/qry     # the listing's registry

kubectl create namespace "$NAMESPACE"

# Keep these: the encryption secret protects every stored credential, and an
# update needs the same values. Stored readable by you alone.
umask 077
cat > qry-secrets.env <<EOF
SECRET_KEY=$(openssl rand -hex 24)
POSTGRES_PASSWORD=$(openssl rand -hex 16)
REDIS_PASSWORD=$(openssl rand -hex 16)
SETUP_CODE=$(openssl rand -hex 8)
EOF
. ./qry-secrets.env

helm template "$APP_INSTANCE_NAME" chart/qry-platform --namespace "$NAMESPACE" \
  --set serviceAccount.create=true \
  --set pythonExecution.rbac.create=true \
  --set backend.image.full="$REGISTRY:$TAG" \
  --set frontend.image.full="$REGISTRY/frontend:$TAG" \
  --set postgresql.image.registry="${REGISTRY%%/*}" \
  --set postgresql.image.repository="${REGISTRY#*/}/postgres" \
  --set postgresql.image.tag="$TAG" \
  --set redis.image.registry="${REGISTRY%%/*}" \
  --set redis.image.repository="${REGISTRY#*/}/redis" \
  --set redis.image.tag="$TAG" \
  --set runtimeImages.pythonExecutor="$REGISTRY/python-executor:$TAG" \
  --set runtimeImages.pythonSession="$REGISTRY/python-session:$TAG" \
  --set backend.secrets.secretKey="$SECRET_KEY" \
  --set postgresql.auth.password="$POSTGRES_PASSWORD" \
  --set redis.auth.password="$REDIS_PASSWORD" \
  --set bootstrap.setupCode="$SETUP_CODE" \
  > "${APP_INSTANCE_NAME}_manifest.yaml"

kubectl apply -n "$NAMESPACE" -f "${APP_INSTANCE_NAME}_manifest.yaml"
```

The manifest holds the secrets too: delete it, or keep it where
`qry-secrets.env` is. The manifest includes a smoke-test pod: once it ends
`Completed`, the backend is ready, the API and the web interface answer, and
Redis refuses a pod without its password.

Open it with `kubectl port-forward -n "$NAMESPACE" svc/qry-frontend 8080:8080`
and `http://localhost:8080`; create the first administrator with `SETUP_CODE`.

With the plan billed by Google the subscription is the license, billed per
monthly active user, and there is nothing to add. The command line needs the
reporting key the console would create: in the listing choose **Deploy via
command line** and **Download service account key**, `kubectl apply -n
"$NAMESPACE"` the downloaded `service-account-key.yaml` before the manifest, and
add `--set googleMarketplace.reportingSecret=<its Secret's name>` (the
`metadata.name` in that file) to the `helm template` command. If the download
fails with "service account ... does not exist", the account was just created
and Google has not finished setting it up: reload the page, pick that account in
**Reporting service account** and download again. A license file from IXEN, pasted
in **Admin › License**, takes precedence. Terms: [qry.dev/eula](https://qry.dev/eula).

## Support

[support.ixen.ai](https://support.ixen.ai)
