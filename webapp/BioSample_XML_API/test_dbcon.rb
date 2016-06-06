require 'pg'
require 'yaml'
require 'pp'

config = YAML.load_file("../db_conf/db_conf.yaml")

# db_user 運用環境のDBのOwner
PG_USER = 'oec'
$pg_user = config["pg_user"]
$pg_port = config["pg_port"]
$pg_host = config["pg_host"]
$pg_bs_name = config["pg_bs_name"]
$pg_pass = config["pg_pass"]

class PGConn
  def conn
    #connection = PG::connect(:host => $pg_host, :user => $pg_user,  :dbname => $pg_bs_name, :port => $pg_port, :password => $pg_pass)
    connection = PGconn.connect($pg_host, $pg_port, '', '',  $pg_bs_name, $pg_user,  $pg_pass)
  end
end

pgc = PGConn.new

co = pgc.conn

puts config