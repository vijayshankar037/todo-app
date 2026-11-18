# Todo App DevOps Practice Guide

This guide covers Docker Compose debugging and deploying the Rails app and
PostgreSQL to a local Kubernetes cluster. The Kubernetes commands use a
dedicated namespace named `todo-practice` so these resources stay separate from
other workloads in the cluster.

> The passwords and Rails secret in the local Compose/Kubernetes configuration
> are for practice only. Do not use them for a real deployment.

## 1. Docker Compose

Run these commands from the project root.

### Start and stop the app

```powershell
# Build the image if needed, then start the app and database in the background
docker compose up --build -d

# Check whether the app and database are running/healthy
docker compose ps

# Follow logs from both services; use Ctrl+C to stop following
docker compose logs -f

# Follow web logs
docker compose logs -f --tail 100 web

# Stop and remove the containers and network (keeps the database volume)
docker compose down
```

Open [http://localhost:3000](http://localhost:3000). The app redirects to the
sign-in page when you are not logged in.

### Interactive container commands

```powershell
# List this project's Compose containers, including stopped ones
docker compose ps -a

# List all containers on the machine
docker ps -a

# Open an interactive shell in the running Rails container
docker compose exec web sh

# Start a temporary shell from the web image if the web container is stopped
docker compose run --rm --no-deps --entrypoint sh web

# Open a shell in the PostgreSQL container
docker compose exec db sh

# Open PostgreSQL's interactive SQL prompt
docker compose exec db psql -U postgres -d todo_app_development
```

The `exec` commands require the target container to be running. Inside the
interactive web shell, use these commands for debugging:

```sh
ps aux
printenv RAILS_ENV PORT
bundle exec rails about
bundle exec rails db:migrate:status
```

In the `psql` prompt:

```sql
\dt
SELECT id, email FROM users;
SELECT id, name, user_id, status FROM tasks;
\q
```

Type `exit` to leave the shell. Alternatively, use the container name displayed
by `docker compose ps` with `docker exec -it <container-name> sh`.

### Container monitoring and debugging

```powershell
# Follow both service logs and stop following with Ctrl+C
docker compose logs --follow --tail 100

# Show only recent Rails or database logs
docker compose logs --tail 200 web
docker compose logs --tail 200 db

# Show detailed container configuration and health-check results
docker inspect todo-app-web-1
docker inspect todo-app-db-1

# Watch live CPU, memory, network, and disk I/O usage for all containers
docker stats

# Show processes running inside each Compose service
docker compose top

# Check whether Rails can connect to PostgreSQL
docker compose exec web bundle exec rails runner "puts ActiveRecord::Base.connection.active?"

# Check PostgreSQL readiness from inside its container
docker compose exec db pg_isready -U postgres -d todo_app_development

# Check the published host port
docker compose port web 3000
```

If a container has exited, `docker compose exec` cannot enter it. Inspect the
exit status and logs, then start or recreate it:

```powershell
# Show stopped containers and their exit state
docker compose ps -a

# Read logs from the failed service
docker compose logs --tail 200 web
docker compose logs --tail 200 db

# Start services again
docker compose up -d
```

Useful recovery commands:

```powershell
# Rebuild and recreate containers
docker compose up --build -d --force-recreate

# Restart one service
docker compose restart web

# Check the fully resolved Compose configuration
docker compose config
```

### Understand and debug Compose volumes

The database service mounts the named volume `postgres_data` at
`/var/lib/postgresql/data` inside the PostgreSQL container. PostgreSQL stores
its database files there, so the data survives container replacement and
`docker compose down`. The volume is managed by Docker and is separate from the
Rails app container.

```powershell
# List volumes and find the one created for this Compose project
docker volume ls

# Inspect the volume details (the project prefix may differ)
docker volume inspect todo-app_postgres_data

# See the mounts attached to the database container
docker inspect todo-app-db-1 --format "{{json .Mounts}}"
```

`docker compose down -v` removes the named volume and permanently deletes this
local practice database. Do not use `-v` if you want to keep its records.

### Understand and debug Compose networking

Compose creates a private project network and attaches both services to it.
The Rails container connects to PostgreSQL using the service name `db` on port
`5432`. Inside the Rails container, `localhost` refers to the Rails container
itself, not PostgreSQL.

The Compose file publishes Rails as `127.0.0.1:3000` on the host mapped to port
`3000` in the web container. This makes the app available at
[http://localhost:3000](http://localhost:3000). PostgreSQL's port is not
published to the host; connect with `docker compose exec db psql ...` instead.

```powershell
# List Docker networks and inspect the Compose network
docker network ls
docker network inspect todo-app_default

# Verify the host-to-container web port mapping
docker compose port web 3000

# Check whether Rails can reach PostgreSQL over the Compose network
docker compose exec web pg_isready -h db -p 5432 -U postgres -d todo_app_development

# Inspect network membership and IP addresses for the web container
docker inspect todo-app-web-1 --format "{{json .NetworkSettings.Networks}}"
```

The Docker network and container names use the Compose project name as a
prefix. If the names above do not exist, find the actual names with
`docker network ls` and `docker compose ps`. Prefer service DNS names such as
`db` over container IP addresses, which can change when containers are
recreated.

## 2. Kubernetes plan

The manifests in `k8s/` create:

| Resource | Purpose |
| --- | --- |
| `postgres` Deployment and Service | PostgreSQL database and in-cluster DNS name |
| `postgres-data` PVC | Persistent database storage |
| `todo-app` Deployment and Service | Rails web app |
| `todo-app-secrets` Secret | Practice database password and Rails secret |
| `todo-app-migrate` Job | Prepares the database schema |

All commands below use the `todo-practice` namespace. Kubernetes names are
namespace-scoped: always pass `-n todo-practice` (or set the current context's
namespace) when inspecting, changing, or deleting these resources.

## 3. Deploy to a local Kubernetes cluster

### Check the cluster and build the image

Make sure Kubernetes is enabled in Docker Desktop, or that Minikube/Kind is
running. Check the active context and nodes:

```powershell
kubectl config current-context
kubectl get nodes
```

Build the image:

```powershell
docker build -t todo-app:local .
```

Make the image available to the Kubernetes nodes:

```powershell
# Minikube
minikube image load todo-app:local

# Kind (use this instead of the Minikube command for a Kind cluster)
kind load docker-image todo-app:local
```

For Docker Desktop Kubernetes, the local Docker image is normally available
directly to the cluster.

### Create the namespace and deploy

Create a separate namespace for this practice deployment:

```powershell
kubectl create namespace todo-practice
```

The command reports `AlreadyExists` if you have already created it; in that
case, continue. Apply the app manifest first because it creates the Secret that
PostgreSQL needs. Then start PostgreSQL and wait for it to be ready:

```powershell
kubectl apply -n todo-practice -f k8s/app.yaml
kubectl apply -n todo-practice -f k8s/postgres.yaml
kubectl rollout status -n todo-practice deployment/postgres --timeout=180s
```

Run the schema preparation Job and wait for completion:

```powershell
kubectl apply -n todo-practice -f k8s/migrate.yaml
kubectl wait -n todo-practice --for=condition=complete job/todo-app-migrate --timeout=180s
```

Wait for the app and inspect the namespace:

```powershell
kubectl rollout status -n todo-practice deployment/todo-app --timeout=180s
kubectl get all,pvc -n todo-practice
```

`k8s/app.yaml` starts the web Deployment before the migration Job is run. Wait
for the migration Job to complete before using the app.

### Open the app

Keep this command running in a terminal:

```powershell
kubectl port-forward -n todo-practice service/todo-app 3000:3000
```

Then browse to [http://localhost:3000](http://localhost:3000). Stop forwarding
with `Ctrl+C`.

## 4. Kubernetes debugging

Use the namespace on every command so you do not accidentally inspect another
deployment:

```powershell
# List workloads, pods, services, PVCs, and Jobs
kubectl get all,pvc,jobs -n todo-practice

# Show labels and which node each pod uses
kubectl get pods -n todo-practice -o wide --show-labels

# Inspect a pod, including events and startup failures
kubectl describe pod -n todo-practice <pod-name>

# Follow app logs
kubectl logs -n todo-practice deployment/todo-app -f

# Follow PostgreSQL logs
kubectl logs -n todo-practice deployment/postgres -f

# Read logs from the migration Job
kubectl logs -n todo-practice job/todo-app-migrate

# Inspect recent namespace events, newest last
kubectl get events -n todo-practice --sort-by=.metadata.creationTimestamp

# Check Deployment rollout state
kubectl rollout status -n todo-practice deployment/todo-app
kubectl rollout status -n todo-practice deployment/postgres
```

If a pod has restarted, inspect the previous container's logs:

```powershell
kubectl logs -n todo-practice <pod-name> --previous
```

If an init container is stuck waiting for PostgreSQL, list its container names
and inspect its logs:

```powershell
kubectl get pod -n todo-practice <pod-name> -o jsonpath="{.spec.initContainers[*].name}"
kubectl logs -n todo-practice <pod-name> -c wait-for-postgres
```

## 5. Open a Kubernetes container and inspect the database

Find pod names:

```powershell
kubectl get pods -n todo-practice
```

Open a shell in the Rails pod:

```powershell
kubectl exec -it -n todo-practice <todo-app-pod-name> -- sh
```

Open `psql` directly in the PostgreSQL pod:

```powershell
kubectl exec -it -n todo-practice deployment/postgres -- psql -U postgres -d todo_app_production
```

At the `psql` prompt:

```sql
\dt
SELECT id, email FROM users;
SELECT id, name, user_id, status FROM tasks;
\q
```

The database may have no users or tasks until you create them through the app.

## 6. Manage the Kubernetes deployment

```powershell
# Scale the web app; do not scale this single-instance practice database
kubectl scale -n todo-practice deployment/todo-app --replicas=3
kubectl get pods -n todo-practice -w

# Scale the app back down
kubectl scale -n todo-practice deployment/todo-app --replicas=1

# Reapply a changed manifest
kubectl apply -n todo-practice -f k8s/app.yaml

# Rebuild and load a changed app image, then restart its Deployment
docker build -t todo-app:local .
minikube image load todo-app:local
kubectl rollout restart -n todo-practice deployment/todo-app
kubectl rollout status -n todo-practice deployment/todo-app
```

For Kind, replace `minikube image load` with `kind load docker-image`. The local
manifests use `imagePullPolicy: IfNotPresent`; use a new image tag when
practicing immutable image updates.

### Rerun the database migration

Kubernetes Jobs cannot be reapplied under the same name after completion. Delete
the old Job, then create it again:

```powershell
kubectl delete job -n todo-practice todo-app-migrate
kubectl apply -n todo-practice -f k8s/migrate.yaml
kubectl wait -n todo-practice --for=condition=complete job/todo-app-migrate --timeout=180s
```

### Remove the practice deployment

Remove the namespaced resources and namespace:

```powershell
kubectl delete namespace todo-practice
```

Deleting the namespace also deletes its PVC and therefore the practice
PostgreSQL data. Back up anything you want to keep before deleting it.
