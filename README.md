# Todo App

Building a Todo App using Ruby on Rails 7, Hotwire and Stimulus.
<table>
  <tr>
    <td>Ruby</td>
    <td>3.1.2</td>
  </tr>
  <tr>
    <td>Rails</td>
    <td>7.0.2.3</td>
  </tr>
  <tr>
    <td>Node</td>
    <td>16.14.2</td>
  </tr>
  <tr>
    <td>NPM</td>
    <td>8.5.0</td>
  </tr>
  <tr>
    <td>Yarn</td>
    <td>1.22.18</td>
  </tr>
  <tr>
    <td>Database</td>
    <td>PostgreSQL</td>
  </tr>
</table>

## Setup

```bash
  # clone the project
  git clone git@github.com:karinevieira/todo-app.git

  # enter the cloned directory
  cd todo-app

  # install Node dependencies
  yarn install

  # create the development and test databases
  rails db:create

  # migrate tables to database
  rails db:migrate

  # run the project
  bin/dev
```
Open the browser at the address http://localhost:3000

## Running Tests

To run tests, run the following command

```bash
  bundle exec rspec
```

## Run with Docker Compose

Build the app image, start the app and PostgreSQL, and prepare the database:

```bash
docker compose up --build
```

Open [http://localhost:3000](http://localhost:3000). Stop the containers with
`Ctrl+C`, then run `docker compose down`. The local PostgreSQL data is kept in a
Docker volume; `docker compose down -v` removes that data.

## Practice deploying to Kubernetes

These manifests are intended for a local Kubernetes cluster. They create a
PostgreSQL Deployment with persistent storage, the Rails Deployment and Service,
and a one-off database migration Job.

Build the image and make it available to your cluster. For Minikube, load the
image after building:

```bash
docker build -t todo-app:local .
minikube image load todo-app:local
```

For Kind, use `kind load docker-image todo-app:local` instead. Docker Desktop
Kubernetes can use the image built by Docker directly.

Apply the app Secret and Service, then PostgreSQL. The app will wait for the
database while it starts:

```bash
kubectl apply -f k8s/app.yaml
kubectl apply -f k8s/postgres.yaml
kubectl apply -f k8s/migrate.yaml
kubectl wait --for=condition=complete job/todo-app-migrate --timeout=180s
kubectl rollout status deployment/todo-app
```

In another terminal, forward the Service port and open
[http://localhost:3000](http://localhost:3000):

```bash
kubectl port-forward service/todo-app 3000:3000
```

Useful practice commands:

```bash
kubectl get pods,services,pvc,jobs
kubectl logs deployment/todo-app
kubectl scale deployment/todo-app --replicas=3
kubectl describe pod <pod-name>
```

The credentials in `k8s/app.yaml` and `compose.yaml` are for local practice only;
replace them and use an appropriate secrets manager for any real deployment.
When rerunning the migration exercise, delete the completed Job first with
`kubectl delete job todo-app-migrate`, then apply `k8s/migrate.yaml` again.
