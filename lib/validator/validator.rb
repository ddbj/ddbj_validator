require 'optparse'
require 'logger'
require 'yaml'
require 'mail'
require 'fileutils'

require File.expand_path('../common/excel2tsv.rb', __FILE__)
require File.expand_path('../common/file_parser.rb', __FILE__)
require File.expand_path('../biosample_validator.rb', __FILE__)
require File.expand_path('../bioproject_validator.rb', __FILE__)
require File.expand_path('../bioproject_tsv_validator.rb', __FILE__)
require File.expand_path('../jvar_validator.rb', __FILE__)
require File.expand_path('../trad_validator.rb', __FILE__)
require File.expand_path('../metabobank_idf_validator.rb', __FILE__)
require File.expand_path('../metabobank_sdrf_validator.rb', __FILE__)

# Validator main class
class Validator
    @@filetype = %w(all_db biosample bioproject submission experiment run analysis jvar vcf trad_anno trad_seq trad_agp metabobank_idf metabobank_sdrf)

    # Runs validator from command line
    # @param [Array] argv command line parameters
    # @return [void]
    def self.run(argv)
      params = Validator.parse_param!(argv)
      new().execute(params)
    end

    # constructor
    def initialize()
      config_file_dir = File.absolute_path(File.dirname(__FILE__) + "/../../conf")
      @version = YAML.load(ERB.new(File.read(config_file_dir + "/version.yml")).result)
      @latest_version = @version["version"]["validator"]
      @setting = YAML.load(ERB.new(File.read(config_file_dir + "/validator.yml")).result)
      @log_file = @setting["api_log"]["path"] + "/validator.log"
      @running_dir = @setting["api_log"]["path"] + "/running/"
      FileUtils.mkdir_p(@running_dir)
      @log = Logger.new(@log_file)
    end

    # Executes validation
    # エラーが発生した場合はエラーメッセージを表示して終了する
    # @param [Hash] params {biosample:"XXXX.xml", bioproject:"YYYY.xml", .., output:"ZZZZ.json"}
    # @return [void]
    def execute(params)
      begin
        @log.info('execute validation:' + params.to_s)
        running_file = @running_dir + "/" + Time.now.strftime("%Y%m%d%H%M%S%L.tmp")
        FileUtils.touch(running_file)

        #get absolute file path and check permission
        permission_error_list = []

        # excelファイルの場合は各シートをTSVに出力してからValidation実行
        unless params[:all_db].nil?
          filetypes = split_excel_sheet(params) # 分割されたfiletype(biosample/bioproject等)のリストを取得
          if filetypes.nil? # ルール違反があった場合は結果JSONが出力されているのでそのまま返す
            return
          else # TSVに変換された場合はそのTSVファイルを validator 実行対象として加える(paramsにmerge)
            filetypes.each do |filetype, path|
              @log.info("splitted sheet validation: #{filetype} => #{path}")
            end
            params.merge!(filetypes)
          end
        end

        params.each do |k,v|
          case k.to_s
          when 'biosample', 'bioproject', 'submision', 'experiment', 'run', 'analysis', 'jvar', 'trad_anno', 'trad_seq', 'trad_agp', 'vcf', 'metabobank_idf', 'metabobank_sdrf', 'output'
            params[k] = File.expand_path(v)
            #TODO check file exist and permission, need write permission to output file
            if k.to_s == 'output'
              dir_path = File.dirname(params[k])
              unless File.writable? dir_path
                permission_error_list.push(params[k])
              end
            else
              unless File.readable? params[k]
                permission_error_list.push(params[k])
              end
            end
          end
        end
        if permission_error_list.size > 0
          @log.error("File not found or permision denied: #{permission_error_list.join(', ')}")
          ret = {status: "error", format: ARGV[1], message: "permision error: #{permission_error_list.join(', ')}"}
          JSON.generate(ret)
          FileUtils.rm(running_file)
          return
        end

        # if exist user/password
        unless params[:user].nil? and params[:password].nil?
          if params[:user] == 'admin' and params[:password] == 'admin'
            #TODO get xml with submission?
          else
            puts "Unauthorized" #return error
            return
          end
        end

        # validate
        ret = {}
        error_list = []
        error_list.concat(validate("biosample", params)) if !params[:biosample].nil?
        error_list.concat(validate("bioproject", params))if !params[:bioproject].nil?
        error_list.concat(validate("jvar", params))if !params[:jvar].nil?
        error_list.concat(validate("vcf", params))if !params[:vcf].nil?
        error_list.concat(validate("trad", params))if (params[:trad_anno] || params[:trad_seq] || params[:trad_agp])
        error_list.concat(validate("metabobank_idf", params))if !params[:metabobank_idf].nil?
        error_list.concat(validate("metabobank_sdrf", params))if !params[:metabobank_sdrf].nil?
        #error_list.concat(validate("combination", params))
        #TODO dra validator

        if error_list.size == 0
          ret = {version: @latest_version, validity: true}
          ret["stats"]  = get_result_stats(error_list)
          ret["messages"] = []
          @log.info('validation result: ' + "success")
        else
          ret = {version: @latest_version, validity: true}

          stats = get_result_stats(error_list)
          ret[:validity] = false if stats[:error_count] > 0
          ret["stats"] = stats
          ret["messages"] = error_list
          @log.info('validation result: ' + "fail")
        end
      rescue => ex
        @log.info('validation result: ' + "error")
        @log.error(ex.message)
        trace = ex.backtrace.map {|row| row}.join("\n")
        @log.error(trace)
        ex.message

        #エラー時のメール送信設定があれば送る
        unless @setting["notification_mail"].nil?
          send_notification_mail(@setting["notification_mail"], ex.message)
        end

        ret = {status: "error", message: ex.message}
      end

      File.open(params[:output], "w") do |file|
        file.puts(JSON.generate(ret))
      end
      FileUtils.rm(running_file)
      JSON.generate(ret)
    end

    def validate(object_type, params)
      if object_type == "trad"
        validator = TradValidator.new
        anno_file = params[:trad_anno]
        seq_file = params[:trad_seq]
        agp_file = params[:trad_agp]
        params = params[:params]
        validator.validate(anno_file, seq_file, agp_file, params);
        validator.error_list
      else
        case object_type
        when "biosample"
          validator = BioSampleValidator.new
          data = params[:biosample]
        when "bioproject" # file formatを検知して振り分ける
          data = params[:bioproject]
          if FileParser.new.get_file_data(data)[:format] == "xml"
            validator = BioProjectValidator.new
          else # json or tsv
            validator = BioProjectTsvValidator.new
          end
        when "jvar"
          validator = JVarValidator.new
          data = params[:jvar]
        when "vcf"
          validator = VCFValidator.new
          data = params[:vcf]
        when "metabobank_idf"
          validator = MetaboBankIdfValidator.new
          data = params[:metabobank_idf]
        when "metabobank_sdrf"
          validator = MetaboBankSdrfValidator.new
          data = params[:metabobank_sdrf]
        when "combination"
          validator = CombinationValidator.new
          data = params
        end
        validator.validate(data, params[:params]);
        validator.error_list
      end
    end

    #
    # Excelファイルをパースして、規定のシートをTSVファイルに変換して出力した結果を返す.
    # 成功した場合は、filetypeと保存TSVファイルのパスを返す.
    # TSV出力が出来なかった場合はnilを返す.
    #
    # ==== Args
    # params: http request parameters
    # ==== Return
    # {bioproject: bioproject_tsv_path, biosample: biosample_tsv_path}
    #
    def split_excel_sheet(params)
      result = nil
      original_excel_path = params[:all_db]
      base_dir = File.dirname(File.expand_path('../', original_excel_path))
      mandatory_sheets = []
      unless params[:params]["check_sheet"].nil?
        if params[:params]["check_sheet"].is_a?(Array)
          mandatory_sheets = params[:params]["check_sheet"]
        else
          mandatory_sheets = params[:params]["check_sheet"].split(",").map{|item| item.chomp.strip}
        end
      end
      # ExcelからTSVへの変換の実行
      split_result = Excel2Tsv.new().split_sheet(original_excel_path, base_dir, mandatory_sheets)
      if split_result[:status] == "failed" # 変換時にルール違反があった場合はfailedとして結果する
        ret = {version: @latest_version, validity: true}
        stats = get_result_stats(split_result[:error_list])
        ret[:validity] = false if stats[:error_count] > 0
        ret["stats"] = stats
        ret["messages"] = split_result[:error_list]
        @log.info('validation result: ' + "fail")
        File.open(params[:output], "w") do |file|
          file.puts(JSON.generate(ret))
        end
      else # 正常に変換できた場合は、Excelに含まれていたfiletypeと出力TSVのファイルパスを返す
        result = split_result[:filetypes]
      end
      result
    end

    # resultのmessageをRuleID毎にグルーピンングしたものを返す
    #
    #[
    # {
    #  "id": "BS_R0013",
    #  "message": "Invalid data format. An automatically-generated correction will be applied.",
    #  "count": 3,
    #  "level": "warning",
    #  "reference": "https://www.ddbj.nig.ac.jp/biosample/validation-e.html#BS_R0013",
    #  "external": false,
    #  "value": [{元の個別メッセージ},{元の個別メッセージ}]
    #  },
    # {
    #  "id": "BS_R0009",
    # }...
    # ]
    #
    def grouped_message(result)
      group_list = []
      result["messages"].each do |msg|
        group_key = msg["id"]
        group_data = group_list.select{|group| group["id"] == group_key}
        if group_data.size == 0
          group_list.push({
                            "id" => group_key,
                            "message" => msg["message"],
                            "count" => 1,
                            "level" => msg["level"],
                            "reference" => msg["reference"],
                            "location_renderer" => msg["location_renderer"],
                            "external" => msg["external"],
                            "value" => [msg]
                          }
          )
        else
          group_data[0]["count"] += 1
          # messageはエラー出現箇所によって差し代わる可能性があり、ルール毎に一意にならない。せめて最も文字列が長いものを優先する。
          group_data[0]["message"] = group_data[0]["message"].size >= msg["message"].size ? group_data[0]["message"] : msg["message"]
          group_data[0]["value"].push(msg)
        end
      end
      result.delete("messages")
      result["grouped_messages"] = group_list
      result
    end

#### Parse the arguments

    # Analyze the arguments of command line
    # @return Hash obtained as a result of analyzing command line arguments
    def self.parse_param!(argv)
      options = {}
      command_parser      = create_command_parser(options)
      # Analyze the arguments
      begin
        command_parser.order! argv
      rescue OptionParser::MissingArgument, OptionParser::InvalidOption, ArgumentError => e
        #TODO return error
        abort e.message
      end
      options
    end

    # Create new OptionParser for this application
    # @return [OptionsParser]
    def self.create_command_parser(options)
      OptionParser.new do |opt|
        opt.banner = "Usage: #{opt.program_name} [-s|--biosample] [-p|--bioproject] [-t|--submission] [-e|--experiment] [-r|--run] [-a|--analysis] -o|--output [--user] [--password]"

        opt.on_head('-h', '--help', 'Show this message') do |v|
          puts opt.help
          exit
        end

        opt.on_head('-v', '--version', 'Show program version') do |v|
          opt.version = "0.9.0" ##TODO conf
          puts opt.ver
          exit
        end

        opt.separator ''
        opt.on('-s VAL', '--biosample=file',  'biosample xml file path')        {|v| options[:biosample] = v}
        opt.on('-p VAL', '--bioproject=file', 'bioproject xml file path')       {|v| options[:bioproject] = v}
        opt.on('-t VAL', '--submission=file', 'submission xml file path')       {|v| options[:submission] = v}
        opt.on('-e VAL', '--experiment=file', 'experiment xml file path')       {|v| options[:experiment] = v}
        opt.on('-r VAL', '--run=file',        'run xml file path')              {|v| options[:run] = v}
        opt.on('-a VAL', '--analysis=file',   'analysis xml file path')         {|v| options[:analysis] = v}
        opt.on('-o VAL', '--output=file',     'output file path')               {|v| options[:output] = v}
        opt.on('--user=VAL',                  'user name')               {|v| options[:output] = v}
        opt.on('--password=VAL',              'password')               {|v| options[:output] = v}
      end
    end

#### Parse the validation result

    #error_listから統計情報を計算して返す
    def get_result_stats (error_list)
      #message(failed_list)の内容をパースして統計情報(stats)を計算
      error_count = error_list.select{|item| item[:level] == "error" }.size
      warning_count = error_list.select{|item| item[:level] == "warning" }.size

      external_error_count = error_list.select{|item| item[:level] == "error" && item[:external] == true }.size
      external_warning_count = error_list.select{|item| item[:level] == "warning" && item[:external] == true }.size
      common_error_count = error_count - external_error_count
      common_warning_count = warning_count - external_warning_count
      error_type_count = {common_error: common_error_count, common_warning: common_warning_count, external_error: external_error_count, external_warning: external_warning_count}

      autocorrect = {}
      #autocorrectできるfileかどうかをのフラグを立てる
      @@filetype.each do |filetype|
        autocorrect_item = error_list.select{|item|
          item[:method].casecmp(filetype) == 0 \
           && item[:annotation].select{|anno| anno[:is_auto_annotation] == true }.size > 0
        }
        if autocorrect_item.size > 0
          autocorrect[filetype] = true
        else
          autocorrect[filetype] = false
        end
      end
      {error_count: error_count, warning_count: warning_count, error_type_count: error_type_count, autocorrect: autocorrect}
    end

#### Error mail
    def send_notification_mail (setting, message)
      smtp_host  = setting["smtp_host"]
      smtp_port  = setting["smtp_port"]
      to  = setting["to"]
      from  = setting["from"]

      options = {
        :address  => smtp_host,
        :port   => smtp_port
      }
      Mail.defaults do
        delivery_method :smtp, options
      end

      body_text = "An error occurred during the validation process. Please check the following message and log file: #{@log_file}\n\n"
      body_text += message

      mail = Mail.new do
        from     "#{from}"
        to       "#{to.join(", ")}"
        subject  "DDBJ validator API error notification"
        body     "#{body_text}"
      end
      mail.deliver!
    end

    private_class_method :create_command_parser
end
