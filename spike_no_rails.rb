require './lib/ddbj_validator'

DDBJValidator.config = {
  'sparql_endpoint' => {'master_endpoint' => 'http://localhost:8890/sparql'},
  'named_graph_uri' => {'taxonomy' => 'http://ddbj.nig.ac.jp/ontologies/taxonomy'},
  'ddbj_rdb'        => {'pg_host' => 'localhost', 'pg_port' => 5432, 'pg_user' => 'x', 'pg_pass' => 'x', 'pg_timeout' => 5},
  'api_log'         => {'path' => 'logs'},
  'biosample'       => {'package_version' => '1.5.0'}
}

DDBJValidator.loader

v = DDBJValidator::BioProjectTsvValidator.new

# Two rules that need neither Virtuoso nor the DDBJ RDB.
# BP_R0062: a value with no field name against it.
bp_data = [{'key' => 'title', 'values' => ['x']}, {'key' => '', 'values' => ['orphaned']}]
v.send :missing_field_name, 'BP_R0062', bp_data

# BP_R0059: a date that is not in a DDBJ-accepted format.
v.send :invalid_data_format, 'BP_R0059', [{'key' => 'public_release_date', 'values' => ['31/12/2026']}]

puts "rules ran with no Rails booted — #{v.error_list.size} finding(s)"
v.error_list.each { puts "  #{it[:id]} (#{it[:level]}) #{it[:message]}" }
