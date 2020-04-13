require 'yaml'

class SubmitterBase

  def initialize
    config_file_dir = File.absolute_path(File.dirname(__FILE__) + "/../../conf")
    setting = YAML.load(ERB.new(File.read(config_file_dir + "/validator.yml")).result)
    config = setting["ddbj_rdb"]

    @pg_host = config["pg_host"]
    @pg_port = config["pg_port"]
    @pg_user = config["pg_user"]
    @pg_pass = config["pg_pass"]
    @pg_timeout = config["pg_timeout"]
  end

  def get_connection(db_name)
    begin
      connection = PG::Connection.connect({host: @pg_host, port: @pg_port, dbname: db_name, user: @pg_user, password: @pg_pass, connect_timeout: @pg_timeout})
      state_timeout = (@pg_timeout * 1000).to_s #millsec
      connection.exec("SET SESSION statement_timeout = #{state_timeout}") ## 一定時間応答がなければエラーを発生させるように設定
      connection
    rescue => ex
      raise ex
    end
  end

end
