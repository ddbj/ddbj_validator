class ValidatorBase 

  def initialize
    @conf = read_common_config(File.absolute_path(File.dirname(__FILE__) + "/../../conf"))
  end

  #
  # 共通設定ファイルの読み込み
  #
  # ==== Args
  # config_file_dir: 設定ファイル設置ディレクトリ
  #
  #
  def read_common_config (config_file_dir)
    config = {}
    begin
      config[:sparql_config] = JSON.parse(File.read(config_file_dir + "/sparql_config.json"))
      config[:ddbj_db_config] = JSON.parse(File.read(config_file_dir + "/ddbj_db_config.json"))
      config
    rescue => ex
      message = "Failed to parse the setting file. Please check the config file below.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
  end
end
