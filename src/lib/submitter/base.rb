require 'yaml'

class SubmitterBase

  def initialize
    config_file_dir = File.absolute_path(File.dirname(__FILE__) + "/../../conf")
    setting = YAML.load(File.read(config_file_dir + "/validator.yml"))
    config = setting["ddbj_rdb"]

    @pg_host = config["pg_host"]
    @pg_port = config["pg_port"]
    @pg_user = config["pg_user"]
    @pg_pass = config["pg_pass"]
  end

end
