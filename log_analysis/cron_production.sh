cat /data1/ddbj/DDBJValidator/validator_production1/shared/log/unicorn_err.log /data1/ddbj/DDBJValidator/validator_production2/shared/log/unicorn_err.log > /data1/ddbj/DDBJValidator/validator_production1/shared/log/unicorn_err_all_node.log
cd /data1/ddbj/DDBJValidator/validator_production1/log_analysis
docker-compose run --rm ruby bundle exec ruby create_log_pg.rb
