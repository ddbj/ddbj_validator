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
If a SPARQL endpoint is provided separately, you do not need to do this, just modify the value of the environment variable `DDBJ_VALIDATOR_APP_VIRTUOSO_ENDPOINT_MASTER`.
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

### Prepare .env file
Create the `.env` file for the environment variables by copying the `template.env` file.
```
$ cp template.env .env
```
A description of each environment variable can be found below in this document.
The environment variables that need to be changed are `DDBJ_VALIDATOR_APP_GOOGLE_API_KEY` and `DDBJ_VALIDATOR_APP_EUTILS_API_KEY`. If these are not changed, several rules in the validator will return errors or warnings for valid values.

## Start containers
```
$ docker-compose up -d
```

## How to use
Specify a file to validate and request to the port specified by `DDBJ_VALIDATOR_APP_PORT` (default: 18840). Then the uuid will be returned.
```
$ curl -F "biosample=@test/data/biosample/105_taxonomy_warning_ng.xml" "http://localhost:18840/api/validation"
{"uuid":"17521682-5890-4acc-ad5d-15891ea3c46e","status":"accepted","start_time":"2021-06-08 20:40:58 +0900"}
```
Request with the returned uuid as a parameter.
```
$ curl "http://localhost:18840/api/validation/17521682-5890-4acc-ad5d-15891ea3c46e"
```
See also API Spec  
* https://localhost:18840/api/apispec/index.html
* https://github.com/ddbj/ddbj_validator/wiki/ValidationAPI%E4%BB%95%E6%A7%98

### From Web app
```
http://localhost:18800/api/client/index
```
## Environment Variables
Environment variables to be written in `.env` files

`UID`  
User ID in the container. You can use `$id` to find out. If it is not changed, then it will run on ROOT.

`GID`  
Group ID in the container. You can use `$id` to find out. If it is not changed, then it will run on ROOT.

`DDBJ_NETWORK_NAME`  
Docker network name. Change the value if the name conflict on the host or if you want to link it with other containers.

`DDBJ_VALIDATOR_APP_CONTAINER_NAME`  
Container name for web app. Change the value if the name conflict on the host.  

`DDBJ_VALIDATOR_APP_IMAGE_NAME`  
Image name for web app. Change the value if the name conflict on the host.  

`DDBJ_VALIDATOR_APP_PORT`  
Port number for web app on host. Change the value if the name conflict on the host.  

`DDBJ_VALIDATOR_APP_VIRTUOSO_ENDPOINT_MASTER`  
SPARQL endpoiint url.  By default, the endpoint url of the virutoso container specified by the variable `DDBJ_VALIDATOR_VIRTUOSO_CONTAINER_NAME`.  

`DDBJ_VALIDATOR_APP_NAMED_GRAPHE_URI_TAXONOMY`  
The namedgraph name that contains the taxonomy in the SPARQL endpoint.

**`PostgreSQL`**  
Some validation rules refer to PostgreSQL data in DDBJ.  By default, it is commented out and the rules that use PostgreSQL will be skipped. Specify these environment variables when PostgreSQL is available.

`DDBJ_VALIDATOR_APP_POSTGRES_HOST`  
Host name or ip address for PostgreSQL. Cannot specify postgresql on localhost from the container.
`DDBJ_VALIDATOR_APP_POSTGRES_PORT`  
Port number for PostgreSQL.

`DDBJ_VALIDATOR_APP_POSTGRES_USER`  
User name for PostgreSQL.

`DDBJ_VALIDATOR_APP_POSTGRES_PASSWD`  
Password for PostgreSQL.

`DDBJ_VALIDATOR_APP_POSTGRES_TIMEOUT`  
Setting of request timeout for PostgreSQL. 30 seconds unless otherwise specified.

`DDBJ_VALIDATOR_APP_BIOSAMPLE_PACKAGE_VERSION`  
Versions of BioSample attributes and package definition information. ,Currently, `1.4.0`, `1.4.1`, `1.5.0` can be specified.

`DDBJ_VALIDATOR_APP_GOOGLE_API_KEY`  
Google API key.  Without this specification, some rules using Google's data (e.g. [BS_R0041] GeocodingAPI for Latlon versus country) will be ignored, even if the value is wrong.

`DDBJ_VALIDATOR_APP_EUTILS_API_KEY`  
API key for NCBI E-utilities. Without this specification, some rules using NCBI data (e.g. [BP_R0014]PMC ID validity) will be ignored, even if the value is wrong. See https://ncbiinsights.ncbi.nlm.nih.gov/2017/11/02/new-api-keys-for-the-e-utilities/

`DDBJ_VALIDATOR_APP_VALIDATOR_LOG_DIR`  
Log directory path. Specify if you want to change from the default location.

`DDBJ_VALIDATOR_APP_SHARED_HOST_DIR`  
The directory path on the host to mount the validation log directory(e.g. validation results) in the container on the host.

`DDBJ_VALIDATOR_APP_VALIDATOR_LOG_HOST_DIR`  
The directory path on the host to mount the `shared` directory(e.g. unicorn's log) in the container on the host.

`DDBJ_VALIDATOR_APP_COLL_DUMP_DIR`  
The directory path on the host to mount the coll_dump directory. coll_dump.txt should includes in this directory.

`DDBJ_VALIDATOR_APP_PUB_REPOSITORY_DIR`
The directory path on the host to mount the pub repository directory. This is the directory created by `git clone https://github.com/ddbj/pub.git`.

`DDBJ_VALIDATOR_APP_MONITORING_SSUB_ID`  
For administration. No changes required.

`DDBJ_VALIDATOR_VIRTUOSO_CONTAINER_NAME`  
Container name for web app. Change the value if the name conflict on the host.

`DDBJ_VALIDATOR_VIRTUOSO_PORT`  
Port number for Virtuoso on host. Change the value if the name conflict on the host.


## Development
### Unit test
Unit testing of rules can be done via docker
```
$ docker compose exec app ruby /usr/src/ddbj_validator/test/lib/validator/test_biosample_validator.rb
```