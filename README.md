# ddbj_validator
DDBJ Validator is a tool for checking the format and violations of data submission files to DDBJ. Currently, only BioSample/BioProject is supported, but DRA/Trad/JVar will be supported in the future.

## Requirement
* docker and docker-compose

## Install
```
$ git clone https://github.com/ddbj/ddbj_validator.git
$ cd ddbj_validator
```

## Prepare
### Download db file
If you prepare SPARQL endpoint as a container on your host, download the latest database file.  
If a SPARQL endpoint is provided separately, you do not need to do this, just modify the value of the environment variable `VIRTUOSO_ENDPOINT_MASTER`.
```
$ curl -Lo "./shared/data/virtuoso/virtuoso.db" "http://ddbj.nig.ac.jp/ontologies/virtuoso.db"
```
### Download coll_dump.txt
```
$ mkdir -p conf/coll_dump
$ curl -o conf/coll_dump/coll_dump.txt "https://ftp.ncbi.nlm.nih.gov/pub/taxonomy/coll_dump.txt"
```

### Download pub repository
```
$ git clone https://github.com/ddbj/pub.git conf/pub
```

## Start containers
`RAILS_ENV` (`development` / `staging` / `production`) and `RAILS_MASTER_KEY` (decrypts `config/credentials/<env>.yml.enc`) must be present in the environment for the staging/production sections of `config/validator.yml`. Everything else has a sensible default in `compose.yaml`.

```
$ RAILS_ENV=production RAILS_MASTER_KEY=... podman-compose up -d
```

## How to use
Specify a file to validate and POST it to the port specified by `APP_PORT` (default: 18840). The response includes the uuid.
```
$ curl -F "biosample=@test/data/biosample/105_taxonomy_warning_ng.xml" "http://localhost:18840/api/validation"
{"uuid":"17521682-5890-4acc-ad5d-15891ea3c46e","status":"accepted","start_time":"2021-06-08 20:40:58 +0900"}
```
Then poll the uuid:
```
$ curl "http://localhost:18840/api/validation/17521682-5890-4acc-ad5d-15891ea3c46e"
```
See also:
* http://localhost:18840/api/apispec/index.html
* https://github.com/ddbj/ddbj_validator/wiki/ValidationAPI%E4%BB%95%E6%A7%98

### From Web app
```
http://localhost:18840/api/client/index
```

## Environment Variables

Read by `compose.yaml`:

| Variable | Default | Purpose |
|---|---|---|
| `RAILS_ENV` | — | Rails environment (`development` / `staging` / `production`). |
| `RAILS_MASTER_KEY` | — | Decrypts `config/credentials/<env>.yml.enc` for staging/production. |
| `APP_PORT` | `18840` | Host port mapped to the app container. |
| `SHARED_HOST_DIR` | `./shared` | Host directory mounted at `/rails/shared` (validation results, etc.). |
| `VIRTUOSO_PORT` | `18841` | Host port mapped to the Virtuoso container. |

Read by `config/validator.yml` in development only (staging / production hardcode these or pull them from credentials):

| Variable | Default | Purpose |
|---|---|---|
| `VIRTUOSO_ENDPOINT_MASTER` | `http://localhost:8890/sparql` | SPARQL endpoint URL. |
| `PGHOST` | `localhost` | DDBJ PostgreSQL host. |
| `PGPORT` | `5432` | DDBJ PostgreSQL port. |
| `PGUSER` | `validator` | DDBJ PostgreSQL user. |
| `PGPASSWORD` | `validator` | DDBJ PostgreSQL password. |

## Development
### Unit test
```
$ bin/rails test
```
