class SubmitterBase
  def initialize
    config = Rails.configuration.validator['ddbj_rdb']

    @pg_host    = config['pg_host']
    @pg_port    = config['pg_port']
    @pg_user    = config['pg_user']
    @pg_pass    = config['pg_pass']
    @pg_timeout = config['pg_timeout']
  end

  def get_connection (db_name)
    connection = PG::Connection.connect(host: @pg_host, port: @pg_port, dbname: db_name, user: @pg_user, password: @pg_pass, connect_timeout: @pg_timeout)
    connection.exec("SET SESSION statement_timeout = #{@pg_timeout * 1000}") # 応答なしで timeout させる設定 (ms)
    connection
  end
end
