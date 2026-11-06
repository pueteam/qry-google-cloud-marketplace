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

```bash
gcloud container clusters get-credentials CLUSTER --region REGION
# Google's Application resource, once per cluster:
kubectl apply -f "https://raw.githubusercontent.com/GoogleCloudPlatform/marketplace-k8s-app-tools/master/crd/app-crd.yaml"

export APP_INSTANCE_NAME=qry
export NAMESPACE=qry
export TAG=0.202.1                              # this repository's version (set at each release)
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
and `http://localhost:8080`; create the first administrator with `SETUP_CODE`,
then add the license IXEN sent you in **Admin › License**.

## Support

[support.ixen.ai](https://support.ixen.ai)
