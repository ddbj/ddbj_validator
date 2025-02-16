cat /data1/w3sabi/DDBJValidator/ddbj_validator_production1/shared/log/unicorn_err.log /data1/w3sabi/DDBJValidator/ddbj_validator_production2/shared/log/unicorn_err.log > /data1/w3sabi/DDBJValidator/ddbj_validator_production1/shared/log/unicorn_err_all_node.log
cd /data1/w3sabi/DDBJValidator/ddbj_validator_production1/log_analysis
podman-compose run --rm ruby bundle exec ruby create_log_pg.rb
