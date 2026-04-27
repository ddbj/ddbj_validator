# ddbj_validator

DDBJ Validator is a Rails 8 API that checks DDBJ submission files (BioSample / BioProject / DRA / Trad / JVar / MetaboBank) against the project's rule set.

## Stack

- Rails 8.1 (API-only) + Puma + Thruster
- Virtuoso SPARQL endpoint (taxonomy / package metadata)
- PostgreSQL on the DDBJ central DB (read-only, used by some rules)
- Sentry for exception reporting

## Development

### Prerequisites

- Ruby 4.0.3 (see `.ruby-version`)
- podman (or docker) to run `compose.test.yaml`, which provides Virtuoso + PostgreSQL with fixtures

### Setup

```sh
git clone https://github.com/ddbj/ddbj_validator.git
cd ddbj_validator
bundle install
docker compose -f compose.test.yaml up -d
docker compose -f compose.test.yaml exec virtuoso isql -U dba -P dba exec='LOAD /fixtures/load.sql;'
```

### Running the server

```sh
bin/rails server
```

Posts go to `http://localhost:3000/api/validation`. `config/validator.yml`'s `development` section reads the standard libpq vars (`PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`) and `VIRTUOSO_ENDPOINT_MASTER`, all with sensible defaults that match `compose.test.yaml`.

### Tests

```sh
bin/rails test
```

PostgreSQL (port 15432) and Virtuoso (port 8890) from `compose.test.yaml` are required — there is no skip path. The suite runs in parallel (`workers: :number_of_processors`).

### Lint / security scan

```sh
bin/rubocop
bin/brakeman
```

Both run in CI alongside the test job.

## API

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/validation` | Submit one or more files, returns `uuid` |
| `GET`  | `/api/validation/:uuid` | Final result |
| `GET`  | `/api/validation/:uuid/status` | Progress |
| `GET`  | `/api/validation/:uuid/:filetype` | Original uploaded file |
| `GET`  | `/api/validation/:uuid/:filetype/autocorrect` | Auto-annotated file |
| `GET`  | `/api/package_list`, `/api/attribute_list`, … | BioSample package / attribute metadata |

Spec: <http://localhost:3000/api/apispec/index.html> · [wiki](https://github.com/ddbj/ddbj_validator/wiki/ValidationAPI%E4%BB%95%E6%A7%98)
Web client: <http://localhost:3000/api/client/index>

Example:

```sh
curl -F 'biosample=@test/data/biosample/105_taxonomy_warning_ng.xml' http://localhost:3000/api/validation
# {"uuid":"17521682-...","status":"accepted","start_time":"..."}
curl http://localhost:3000/api/validation/17521682-...
```

## Production / staging deployment

Deployment is driven by `bin/deploy <env>` (which rsyncs to each instance directory under `/data1/w3sabi/DDBJValidator/` on the deploy host) and `bin/deploy-remote.sh` (which rebuilds the app image, restarts the container with `podman-compose`, and probes `/api/monitoring`). Each environment hosts up to two instances (`staging1`/`staging2`, `production1`/`production2`); they share `compose.yaml` but have separate per-instance `.env` files.

### Required env vars (`.env` per instance)

| Variable | Default | Purpose |
|---|---|---|
| `RAILS_ENV` | — | `staging` or `production` |
| `RAILS_MASTER_KEY` | — | Decrypts `config/credentials/<env>.yml.enc` (PG password, Sentry DSN) |
| `APP_PORT` | `18840` | Host port mapped to the app container; `bin/deploy-remote.sh` uses it for the `/api/monitoring` probe |
| `SHARED_HOST_DIR` | `./shared` | Host directory mounted at `/rails/shared` |
| `VIRTUOSO_PORT` | `18841` | Host port mapped to the Virtuoso container |

DDBJ DB hostname/port/user, Virtuoso endpoint, and the named graph URI are hardcoded per environment in `config/validator.yml`. Edit secrets with:

```sh
bin/rails credentials:edit --environment <env>
```

### Logs / monitoring

- Application logs go to STDOUT via `ActiveSupport::TaggedLogging.logger(STDOUT)`; `podman logs <app>` is the operator's tail.
- Unhandled exceptions reach Sentry through `ApplicationController#rescue_from` → `Rails.error.report` (sentry-rails subscribes to the Rails error reporter).
- `/api/monitoring` runs a full BioSample validation cycle end-to-end and returns 503 if anything in the pipeline is unhealthy.
