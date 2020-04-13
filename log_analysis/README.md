```
$ mkdir data
$ vi .env
$ docker-compose up -d
$ docker-compose run --rm ruby bundle exec ruby create_log_pg.rb "2020-03-08"
```
