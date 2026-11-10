{{/*
=============================================================================
Qry Platform - Helm Template Helpers
=============================================================================
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "qry.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "qry.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "qry.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "qry.labels" -}}
helm.sh/chart: {{ include "qry.chart" . }}
{{ include "qry.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "qry.selectorLabels" -}}
app.kubernetes.io/name: {{ include "qry.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
=============================================================================
Image Helpers
=============================================================================
*/}}

{{/*
Full image path for a component
Usage: {{ include "qry.image" (dict "component" .Values.backend "global" .Values) }}
*/}}
{{- define "qry.image" -}}
{{- $tag := .component.image.tag | default .global.image.tag }}
{{- printf "%s:%s" (include "qry.imagePath" (dict "image" .global.image "name" .component.image.name)) $tag }}
{{- end }}

{{/*
registry/project/repository/name with the empty parts left out: Artifact
Registry has all four (europe-southwest1-docker.pkg.dev/pue-madrid/puedata/
qry-backend), registry.qry.dev has two (registry.qry.dev/qry/qry-backend:
registry registry.qry.dev, project qry, repository ""). With every part
joined, an empty one gave "registry.qry.dev/qry//qry-backend", so the only
way to pull from there was image.full, which also froze the tag.
*/}}
{{- define "qry.imagePath" -}}
{{- $parts := list -}}
{{- range (list .image.registry .image.project .image.repository .name) -}}
{{- if . }}{{ $parts = append $parts . }}{{ end -}}
{{- end -}}
{{- join "/" $parts -}}
{{- end }}

{{/*
Backend image
*/}}
{{- /* backend.image.full, when set, is the whole reference: how a
       marketplace hands over the image it serves from its own registry. */}}
{{- define "qry.backendImage" -}}
{{- if .Values.backend.image.full -}}
{{- .Values.backend.image.full }}
{{- else -}}
{{- $tag := .Values.backend.image.tag | default .Values.image.tag }}
{{- printf "%s:%s" (include "qry.imagePath" (dict "image" .Values.image "name" .Values.backend.image.name)) $tag }}
{{- end -}}
{{- end }}

{{/*
Frontend image
*/}}
{{- define "qry.frontendImage" -}}
{{- if .Values.frontend.image.full -}}
{{- .Values.frontend.image.full }}
{{- else -}}
{{- $tag := .Values.frontend.image.tag | default .Values.image.tag }}
{{- printf "%s:%s" (include "qry.imagePath" (dict "image" .Values.image "name" .Values.frontend.image.name)) $tag }}
{{- end -}}
{{- end }}

{{/*
Image pull policy
*/}}
{{- define "qry.imagePullPolicy" -}}
{{- .Values.image.pullPolicy | default "Always" }}
{{- end }}

{{/*
=============================================================================
Database Helpers
=============================================================================
*/}}

{{/*
PostgreSQL host and port: the chart's own, or a managed server
(postgresql.enabled=false + postgresql.external.host). Without external.host
it stays "postgres": installations predating it (ixenlab, our Autopilot
tenants) turn the chart's server off and point a Service of that name at the
managed one (kubernetes/tenants/templates/shim-services), and must keep
rendering exactly as before.
*/}}
{{- define "qry.postgresExternal" -}}
{{- if and (not .Values.postgresql.enabled) .Values.postgresql.external.host -}}true{{- end -}}
{{- end }}

{{- define "qry.postgresHost" -}}
{{- if include "qry.postgresExternal" . -}}{{ .Values.postgresql.external.host }}{{- else -}}postgres{{- end -}}
{{- end }}

{{- define "qry.postgresPort" -}}
{{- if include "qry.postgresExternal" . -}}{{ .Values.postgresql.external.port | default 5432 }}{{- else -}}5432{{- end -}}
{{- end }}

{{/*
TLS for a managed server (Azure Flexible Server, Cloud SQL...). asyncpg
spells it ssl=, libpq sslmode=; empty: none, as for the in-chart server.
*/}}
{{- define "qry.postgresSslMode" -}}
{{- if include "qry.postgresExternal" . -}}{{ .Values.postgresql.external.sslMode | default "" }}{{- end -}}
{{- end }}

{{/*
The chart's own PostgreSQL and Redis passwords when the values give none.
Installations used to start with PostgreSQL's "qry2024lab" and a Redis with no
password at all; now an existing one is kept (read from what the cluster
runs) and a new installation gets a random one. Sets .Values so every template
of the render sees the same value; called by everything that reads them.

Kept: Redis from its Secret qry-redis-auth; PostgreSQL from its StatefulSet's
POSTGRES_PASSWORD (an installation on the old default keeps it - a running
database cannot change it this way). Generated only with access to the cluster
(helm install/upgrade): `helm template` (Argo CD, a marketplace's deployer)
cannot read it back, and a password new on every render would lock the backend
out of a database initialised with the first one - so PostgreSQL then needs
postgresql.auth.password, and Redis keeps running without one unless given.
*/}}
{{- define "qry.resolvePasswords" -}}
{{- $ns := include "qry.namespace" . -}}
{{- $cluster := lookup "v1" "ServiceAccount" $ns "default" -}}
{{- if and .Values.redis.enabled (not .Values.redis.auth.password) -}}
{{- $s := lookup "v1" "Secret" $ns "qry-redis-auth" -}}
{{- if and $s $s.data (index $s.data "password") -}}
{{- $_ := set .Values.redis.auth "password" (index $s.data "password" | b64dec) -}}
{{- else if and $cluster .Release.IsInstall -}}
{{- $_ := set .Values.redis.auth "password" (randAlphaNum 32) -}}
{{- end -}}
{{- end -}}
{{- if and .Values.postgresql.enabled (not .Values.postgresql.auth.password) -}}
{{- $found := "" -}}
{{- $sts := lookup "apps/v1" "StatefulSet" $ns "postgres" -}}
{{- if $sts -}}
{{- range $c := $sts.spec.template.spec.containers -}}
{{- range $e := ($c.env | default list) -}}
{{- if eq $e.name "POSTGRES_PASSWORD" -}}{{- $found = ($e.value | default "") -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if $found -}}
{{- $_ := set .Values.postgresql.auth "password" $found -}}
{{- else if and $cluster .Release.IsInstall -}}
{{- $_ := set .Values.postgresql.auth "password" (randAlphaNum 32) -}}
{{- else -}}
{{- fail "postgresql.auth.password is required: the chart's PostgreSQL has no default password, and one cannot be generated here (helm template, or an upgrade that finds no running database)." -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
PostgreSQL async connection URL (for SQLAlchemy async). The password is
URL-encoded: one with @ or / used to break the URL.
*/}}
{{- define "qry.databaseUrl" -}}
{{- include "qry.resolvePasswords" . -}}
{{- $ssl := include "qry.postgresSslMode" . }}
{{- printf "postgresql+asyncpg://%s:%s@%s:%s/%s%s" .Values.postgresql.auth.username (urlquery .Values.postgresql.auth.password | replace "+" "%20") (include "qry.postgresHost" .) (include "qry.postgresPort" .) .Values.postgresql.auth.database (ternary (printf "?ssl=%s" $ssl) "" (ne $ssl "")) }}
{{- end }}

{{/*
PostgreSQL standard connection URL (for psql)
*/}}
{{- define "qry.databaseUrlStandard" -}}
{{- include "qry.resolvePasswords" . -}}
{{- $ssl := include "qry.postgresSslMode" . }}
{{- printf "postgresql://%s:%s@%s:%s/%s%s" .Values.postgresql.auth.username (urlquery .Values.postgresql.auth.password | replace "+" "%20") (include "qry.postgresHost" .) (include "qry.postgresPort" .) .Values.postgresql.auth.database (ternary (printf "?sslmode=%s" $ssl) "" (ne $ssl "")) }}
{{- end }}

{{/*
=============================================================================
Redis Helpers
=============================================================================
*/}}

{{- define "qry.redisExternal" -}}
{{- if and (not .Values.redis.enabled) .Values.redis.external.host -}}true{{- end -}}
{{- end }}

{{/* Without external.host it stays "redis", the shim Service older installations use. */}}
{{- define "qry.redisHost" -}}
{{- if include "qry.redisExternal" . -}}{{ .Values.redis.external.host }}{{- else -}}redis{{- end -}}
{{- end }}

{{/*
Redis connection URL: the chart's own, or a managed one. A managed Redis
(Azure Managed Redis, Memorystore with TLS) takes rediss:// and a password;
ssl_cert_reqs=required is what Celery's broker needs to accept rediss.
*/}}
{{- define "qry.redisUrl" -}}
{{- include "qry.resolvePasswords" . -}}
{{- if not (include "qry.redisExternal" .) -}}
{{- $pw := .Values.redis.auth.password | default "" -}}
{{- if and .Values.redis.enabled $pw -}}
{{- printf "redis://:%s@%s:6379/0" (urlquery $pw | replace "+" "%20") (include "qry.redisHost" .) }}
{{- else -}}
{{- printf "redis://%s:6379/0" (include "qry.redisHost" .) }}
{{- end -}}
{{- else -}}
{{- $e := .Values.redis.external -}}
{{- $auth := ternary (printf ":%s@" (urlquery ($e.password | default "") | replace "+" "%20")) "" (ne ($e.password | default "") "") -}}
{{- if $e.tls -}}
{{- printf "rediss://%s%s:%v/%v?ssl_cert_reqs=required" $auth (include "qry.redisHost" .) ($e.port | default 6380) ($e.db | default 0) }}
{{- else -}}
{{- printf "redis://%s%s:%v/%v" $auth (include "qry.redisHost" .) ($e.port | default 6379) ($e.db | default 0) }}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
An image from the chart's own registry override: "registry/repository:tag",
or "repository:tag" when no registry is set (Docker Hub, as before).
*/}}
{{- define "qry.thirdPartyImage" -}}
{{- if .registry -}}{{ printf "%s/%s:%s" .registry .repository .tag }}{{- else -}}{{ printf "%s:%s" .repository .tag }}{{- end -}}
{{- end }}

{{/*
=============================================================================
Secret and Volume Helpers
=============================================================================
*/}}

{{/*
Image pull secrets
*/}}
{{- define "qry.imagePullSecrets" -}}
{{- if .Values.imagePullSecret.create }}
- name: {{ .Values.imagePullSecret.name }}
{{- end }}
{{- end }}

{{/*
Common environment variables for all backend-based containers

CONFIGURATION SYSTEM (as of v1.5.0):
All credentials and application settings are stored in the database and
configured via Admin > System Settings after deployment.

RuntimeConfigProvider:
- Loads GCP credentials from database, writes to temp file, sets GOOGLE_APPLICATION_CREDENTIALS
- Loads license credentials from database, writes to temp file, sets LICENSE_CREDENTIALS
- Extracts project_id from GCP credentials JSON automatically

Only infrastructure connectivity env vars are needed here:
- DATABASE_URL: PostgreSQL connection (required at startup)
- REDIS_URL: Redis connection (required at startup)
- ENVIRONMENT: Deployment environment name
*/}}
{{- define "qry.commonEnv" -}}
- name: ENVIRONMENT
  value: {{ .Values.global.environment | quote }}
- name: DATABASE_URL
  value: {{ include "qry.databaseUrl" . | quote }}
- name: REDIS_URL
  value: {{ include "qry.redisUrl" . | quote }}
- name: SCHEMA_REFRESH_INTERVAL
  value: {{ .Values.cronjobs.schemaRefresh.cacheTtlSeconds | default 90000 | quote }}
{{- end }}

{{/*
=============================================================================
Component-specific Labels
=============================================================================
*/}}

{{/*
Backend labels
*/}}
{{- define "qry.backend.labels" -}}
{{ include "qry.labels" . }}
app.kubernetes.io/component: backend
{{- end }}

{{/*
Backend selector labels
*/}}
{{- define "qry.backend.selectorLabels" -}}
app: qry-backend
{{- end }}

{{/*
Frontend labels
*/}}
{{- define "qry.frontend.labels" -}}
{{ include "qry.labels" . }}
app.kubernetes.io/component: frontend
{{- end }}

{{/*
Frontend selector labels
*/}}
{{- define "qry.frontend.selectorLabels" -}}
app: qry-frontend
{{- end }}

{{/*
Celery worker labels
*/}}
{{- define "qry.celeryWorker.labels" -}}
{{ include "qry.labels" . }}
app.kubernetes.io/component: celery-worker
{{- end }}

{{/*
Celery worker selector labels
*/}}
{{- define "qry.celeryWorker.selectorLabels" -}}
app: celery-worker
component: worker
{{- end }}

{{/*
Queues for the general-purpose celery worker.

Subtracts whatever the heavy worker owns, so enabling celeryHeavyWorker moves
those queues instead of double-serving them. Doing the subtraction here (rather
than expecting operators to also override celeryWorker.queues) matters because
tenants upgrade with --reuse-values: their stored queue list would otherwise
keep pulling dataflow/lakeflow into the same pod as the scheduled notebooks.
*/}}
{{- define "qry.celeryWorker.queues" -}}
{{- $queues := list -}}
{{- range $q := splitList "," (.Values.celeryWorker | default dict).queues -}}
{{- $trimmed := trim $q -}}
{{- if $trimmed -}}{{- $queues = append $queues $trimmed -}}{{- end -}}
{{- end -}}
{{/*
  default dict: `helm upgrade --reuse-values` bases the render on the previous
  release's values and does NOT merge in the new chart's defaults, so any key
  introduced after the deployed release is simply absent. Reaching into a nil
  map aborts the whole upgrade with "nil pointer evaluating interface {}",
  which is what celeryHeavyWorker did to tenants on older releases.
*/}}
{{- $heavy := .Values.celeryHeavyWorker | default dict -}}
{{- if $heavy.enabled -}}
{{- range $q := splitList "," ($heavy.queues | default "") -}}
{{- $queues = without $queues (trim $q) -}}
{{- end -}}
{{- end -}}
{{- if $queues -}}
{{- join "," $queues -}}
{{- else -}}
default
{{- end -}}
{{- end }}

{{/*
Celery beat labels
*/}}
{{- define "qry.celeryBeat.labels" -}}
{{ include "qry.labels" . }}
app.kubernetes.io/component: celery-beat
{{- end }}

{{/*
Celery beat selector labels
*/}}
{{- define "qry.celeryBeat.selectorLabels" -}}
app: celery-beat
component: scheduler
{{- end }}

{{/*
Qry worker labels
*/}}
{{- define "qry.qryWorker.labels" -}}
{{ include "qry.labels" . }}
app.kubernetes.io/component: qry-worker
{{- end }}

{{/*
Qry worker selector labels
*/}}
{{- define "qry.qryWorker.selectorLabels" -}}
app: qry-worker
{{- end }}

{{/*
Telegram bot labels (issue #262 — messaging gateway).
The bot is a single-replica long-poller; scaling beyond one pod
would race the Telegram getUpdates offset (only one client may
poll a given bot token at a time).
*/}}
{{- define "qry.telegramBot.labels" -}}
{{ include "qry.labels" . }}
app.kubernetes.io/component: telegram-bot
{{- end }}

{{/*
Telegram bot selector labels
*/}}
{{- define "qry.telegramBot.selectorLabels" -}}
app: qry-telegram-bot
{{- end }}

{{/*
PostgreSQL labels
*/}}
{{- define "qry.postgres.labels" -}}
{{ include "qry.labels" . }}
app.kubernetes.io/component: postgresql
{{- end }}

{{/*
PostgreSQL selector labels
*/}}
{{- define "qry.postgres.selectorLabels" -}}
app: postgres
{{- end }}

{{/*
Redis labels
*/}}
{{- define "qry.redis.labels" -}}
{{ include "qry.labels" . }}
app.kubernetes.io/component: redis
{{- end }}

{{/*
Redis selector labels
*/}}
{{- define "qry.redis.selectorLabels" -}}
app: redis
{{- end }}

{{/*
=============================================================================
Namespace Helpers
=============================================================================
*/}}

{{/*
Main application namespace
*/}}
{{- define "qry.namespace" -}}
{{- .Values.global.namespace | default .Release.Namespace }}
{{- end }}

{{/*
Python execution namespace
*/}}
{{- define "qry.pythonExecution.namespace" -}}
{{- if .Values.pythonExecution.singleNamespace -}}
{{- include "qry.namespace" . }}
{{- else -}}
{{- .Values.pythonExecution.namespace }}
{{- end -}}
{{- end }}

{{/*
=============================================================================
Storage Class Helper
=============================================================================
*/}}

{{/*
Storage class name
*/}}
{{- define "qry.storageClass" -}}
{{- if .Values.global.storageClass }}
{{- .Values.global.storageClass }}
{{- else }}
{{- "" }}
{{- end }}
{{- end }}

{{/*
Optional extra envFrom source when the JWT secret is managed outside the
chart. Listed AFTER qry-backend-secrets on every workload: for envFrom the
last source wins, so the external JWT_SECRET_KEY takes precedence.
*/}}
{{- define "qry.existingSecretEnvFrom" -}}
{{- with .Values.backend.secrets.existingSecret -}}
- secretRef:
    name: {{ . | quote }}
{{- end -}}
{{- end -}}

{{/*
Pod- and container-level securityContext for workloads on the backend image.
Values-driven so a tenant with a stricter (or looser) admission policy can
adjust without editing templates. Empty maps render nothing.
*/}}
{{- define "qry.backendPodSecurityContext" -}}
{{- with .Values.backendSecurity.pod }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{- define "qry.backendContainerSecurityContext" -}}
{{- with .Values.backendSecurity.container }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
topologySpreadConstraints for a workload. Args (dict): root, replicas, labels
(a map used as the label selector). Renders nothing unless enabled and the
workload runs more than one replica — see `availability` in values.yaml.
*/}}
{{- define "qry.topologySpread" -}}
{{- $av := .root.Values.availability | default dict }}
{{- $ts := $av.topologySpread | default dict }}
{{- if and $ts.enabled (gt (int .replicas) 1) }}
topologySpreadConstraints:
  - maxSkew: {{ $ts.maxSkew | default 1 }}
    topologyKey: {{ $ts.topologyKey | default "kubernetes.io/hostname" }}
    whenUnsatisfiable: {{ $ts.whenUnsatisfiable | default "ScheduleAnyway" }}
    labelSelector:
      matchLabels:
        {{- toYaml .labels | nindent 8 }}
{{- end }}
{{- end }}

{{/*
A PodDisruptionBudget for a workload. Args (dict): root, name, replicas,
labels. Same gate as qry.topologySpread.
*/}}
{{- define "qry.pdb" -}}
{{- $av := .root.Values.availability | default dict }}
{{- $pdb := $av.podDisruptionBudget | default dict }}
{{- if and $pdb.enabled (gt (int .replicas) 1) }}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ .name }}
  namespace: {{ include "qry.namespace" .root }}
  labels:
    {{- include "qry.labels" .root | nindent 4 }}
    app.kubernetes.io/component: {{ .name }}
spec:
  minAvailable: {{ $pdb.minAvailable | default 1 }}
  selector:
    matchLabels:
      {{- toYaml .labels | nindent 6 }}
{{- end }}
{{- end }}

{{/*
Checksums that make a changed secret replace the pods reading it (they read it
only at start; a password changed with helm upgrade left the backend on the old
one). The backend secret carries the database and Redis URLs, so it covers both
passwords. Redis gets its password's alone, so other secret changes do not
restart it and drop its queues. Truncated hashes: nothing to read back.
*/}}
{{- define "qry.secretsChecksum" -}}
{{- include (print $.Template.BasePath "/secrets/backend-secrets.yaml") . | sha256sum | trunc 16 | quote -}}
{{- end }}

{{/*
The address people reach Qry at, offered to the first-run screen as a default:
bootstrap.publicUrl, else the first ingress host (https when it has a tls entry).
Empty when neither is set; the setup screen then proposes the browser's address.
*/}}
{{- define "qry.publicUrl" -}}
{{- if .Values.bootstrap.publicUrl -}}
{{- .Values.bootstrap.publicUrl | trimSuffix "/" -}}
{{- else if and .Values.ingress.enabled .Values.ingress.hosts -}}
{{- $host := (index .Values.ingress.hosts 0).host -}}
{{- if .Values.ingress.tls -}}https{{- else -}}http{{- end -}}://{{ $host }}
{{- end -}}
{{- end }}

{{- define "qry.redisPasswordChecksum" -}}
{{- include "qry.resolvePasswords" . -}}
{{- .Values.redis.auth.password | default "" | sha256sum | trunc 16 | quote -}}
{{- end }}

{{/*
The image pull secret's .dockerconfigjson, base64. The password is trimmed:
a license passed with --set-file keeps the file's final newline, and
containerd then refuses the Authorization header ("invalid header field
value") and every pull fails.
*/}}
{{- define "qry.dockerConfigJson" -}}
{{- $s := .Values.imagePullSecret -}}
{{- $password := $s.dockerPassword | trim -}}
{{- $auth := dict "username" $s.dockerUsername "password" $password "email" $s.dockerEmail "auth" (printf "%s:%s" $s.dockerUsername $password | b64enc) -}}
{{- dict "auths" (dict $s.dockerServer $auth) | toJson | b64enc -}}
{{- end }}

{{/*
The pull secret's annotations and data. The backend writes the license saved
in Admin > License into the secret's `license` entries and marks it with
qry.dev/registry-license (app/services/registry_pull_secret.py); a marked
secret is kept as it is, or every helm upgrade would put back the license the
chart was installed with. Unmarked (a new install, a service-account key): from
values. Call with (dict "root" $ "namespace" <ns>).
*/}}
{{- define "qry.pullSecretFields" -}}
{{- $root := .root -}}
{{- $live := lookup "v1" "Secret" .namespace $root.Values.imagePullSecret.name | default dict -}}
{{- $synced := dig "metadata" "annotations" "qry.dev/registry-license" "" $live -}}
{{- if and $synced (dig "data" ".dockerconfigjson" "" $live) }}
metadata_annotations:
  qry.dev/registry-license: {{ $synced | quote }}
dockerconfigjson: {{ index $live.data ".dockerconfigjson" }}
{{- else }}
dockerconfigjson: {{ include "qry.dockerConfigJson" $root }}
{{- end }}
{{- end }}
