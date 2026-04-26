require 'logger'
require 'securerandom'
require 'yaml'
require 'fileutils'

# Validator main class
class Validator
    FILETYPES = %w[all_db biosample bioproject submission experiment run analysis jvar trad_anno trad_seq trad_agp metabobank_idf metabobank_sdrf].freeze

    # constructor
    def initialize
      @version = YAML.load(ERB.new(File.read(File.expand_path('../../conf/version.yml', __dir__))).result)
      @latest_version = @version['version']['validator']
      @setting = Rails.configuration.validator
      @log_file = @setting['api_log']['path'] + '/validator.log'
      @running_dir = @setting['api_log']['path'] + '/running/'
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
        running_file = @running_dir + '/' + Time.now.strftime('%Y%m%d%H%M%S%L.tmp')
        FileUtils.touch(running_file)

        # get absolute file path and check permission
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

        params.each do |k, v|
          case k.to_s
          when 'biosample', 'bioproject', 'submission', 'experiment', 'run', 'analysis', 'jvar', 'trad_anno', 'trad_seq', 'trad_agp', 'metabobank_idf', 'metabobank_sdrf', 'output'
            params[k] = File.expand_path(v)
            # TODO check file exist and permission, need write permission to output file
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
        if permission_error_list.any?
          @log.error("File not found or permision denied: #{permission_error_list.join(', ')}")
          ret = {status: 'error', format: ARGV[1], message: "permision error: #{permission_error_list.join(', ')}"}
          JSON.generate(ret)
          FileUtils.rm(running_file)
          return
        end

        # validate
        ret = {}
        error_list = []
        error_list.concat(validate('biosample', params)) if !params[:biosample].nil?
        error_list.concat(validate('bioproject', params)) if !params[:bioproject].nil?
        error_list.concat(validate('jvar', params)) if !params[:jvar].nil?
        error_list.concat(validate('trad', params)) if params[:trad_anno] || params[:trad_seq] || params[:trad_agp]
        error_list.concat(validate('metabobank_idf', params)) if !params[:metabobank_idf].nil?
        error_list.concat(validate('metabobank_sdrf', params)) if !params[:metabobank_sdrf].nil?
        # error_list.concat(validate("combination", params))
        # TODO dra validator

        if error_list.empty?
          ret = {version: @latest_version, validity: true}
          ret['stats']  = get_result_stats(error_list)
          ret['messages'] = []
          @log.info('validation result: ' + 'success')
        else
          ret = {version: @latest_version, validity: true}

          stats = get_result_stats(error_list)
          ret[:validity] = false if stats[:error_count] > 0
          ret['stats'] = stats
          ret['messages'] = error_list
          @log.info('validation result: ' + 'fail')
        end
      rescue => ex
        @log.info('validation result: ' + 'error')
        @log.error(ex.message)
        trace = ex.backtrace.join("\n")
        @log.error(trace)
        ex.message

        # エラー時のメール送信設定があれば送る
        unless @setting['notification_mail'].nil?
          send_notification_mail(@setting['notification_mail'], ex.message)
        end

        ret = {status: 'error', message: ex.message}
      end

      atomic_write(params[:output], JSON.generate(ret))
      FileUtils.rm(running_file)
      JSON.generate(ret)
    end

    def validate(object_type, params)
      if object_type == 'trad'
        validator = TradValidator.new
        anno_file = params[:trad_anno]
        seq_file = params[:trad_seq]
        agp_file = params[:trad_agp]
        params = params[:params]
        validator.validate(anno_file, seq_file, agp_file, params)
        validator.error_list
      else
        case object_type
        when 'biosample'
          validator = BioSampleValidator.new
          data = params[:biosample]
        when 'bioproject' # file formatを検知して振り分ける
          data = params[:bioproject]
          if FileParser.new.get_file_data(data)[:format] == 'xml'
            validator = BioProjectValidator.new
          else # json or tsv
            validator = BioProjectTsvValidator.new
          end
        when 'jvar'
          validator = JVarValidator.new
          data = params[:jvar]
        when 'metabobank_idf'
          validator = MetaboBankIdfValidator.new
          data = params[:metabobank_idf]
        when 'metabobank_sdrf'
          validator = MetaboBankSdrfValidator.new
          data = params[:metabobank_sdrf]
        when 'combination'
          validator = CombinationValidator.new
          data = params
        end
        validator.validate(data, params[:params])
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
      unless params[:params]['check_sheet'].nil?
        if params[:params]['check_sheet'].is_a?(Array)
          mandatory_sheets = params[:params]['check_sheet']
        else
          mandatory_sheets = params[:params]['check_sheet'].split(',').map {|item| item.chomp.strip }
        end
      end
      # ExcelからTSVへの変換の実行
      split_result = Excel2Tsv.new().split_sheet(original_excel_path, base_dir, mandatory_sheets)
      if split_result[:status] == 'failed' # 変換時にルール違反があった場合はfailedとして結果する
        ret = {version: @latest_version, validity: true}
        stats = get_result_stats(split_result[:error_list])
        ret[:validity] = false if stats[:error_count] > 0
        ret['stats'] = stats
        ret['messages'] = split_result[:error_list]
        @log.info('validation result: ' + 'fail')
        atomic_write(params[:output], JSON.generate(ret))
      else # 正常に変換できた場合は、Excelに含まれていたfiletypeと出力TSVのファイルパスを返す
        result = split_result[:filetypes]
      end
      result
    end

    # resultのmessageをRuleID毎にグルーピンングしたものを返す
    #
    # [
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
      result['messages'].each do |msg|
        group_key = msg['id']
        group_data = group_list.select {|group| group['id'] == group_key }
        if group_data.empty?
          group_list.push({
                            'id' => group_key,
                            'message' => msg['message'],
                            'count' => 1,
                            'level' => msg['level'],
                            'reference' => msg['reference'],
                            'location_renderer' => msg['location_renderer'],
                            'external' => msg['external'],
                            'value' => [msg]
                          }
          )
        else
          group_data[0]['count'] += 1
          # messageはエラー出現箇所によって差し代わる可能性があり、ルール毎に一意にならない。せめて最も文字列が長いものを優先する。
          group_data[0]['message'] = group_data[0]['message'].size >= msg['message'].size ? group_data[0]['message'] : msg['message']
          group_data[0]['value'].push(msg)
        end
      end
      result.delete('messages')
      result['grouped_messages'] = group_list
      result
    end

    #### Parse the validation result

    # error_listから統計情報を計算して返す
    def get_result_stats (error_list)
      # message(failed_list)の内容をパースして統計情報(stats)を計算
      error_count = error_list.select {|item| item[:level] == 'error' }.size
      warning_count = error_list.select {|item| item[:level] == 'warning' }.size

      external_error_count = error_list.select {|item| item[:level] == 'error' && item[:external] == true }.size
      external_warning_count = error_list.select {|item| item[:level] == 'warning' && item[:external] == true }.size
      common_error_count = error_count - external_error_count
      common_warning_count = warning_count - external_warning_count
      error_type_count = {common_error: common_error_count, common_warning: common_warning_count, external_error: external_error_count, external_warning: external_warning_count}

      autocorrect = {}
      # autocorrectできるfileかどうかをのフラグを立てる
      FILETYPES.each do |filetype|
        autocorrect_item = error_list.select {|item|
          item[:method].casecmp(filetype) == 0 \
           && item[:annotation].any? {|anno| anno[:is_auto_annotation] == true }
        }
        if autocorrect_item.any?
          autocorrect[filetype] = true
        else
          autocorrect[filetype] = false
        end
      end
      {error_count: error_count, warning_count: warning_count, error_type_count: error_type_count, autocorrect: autocorrect}
    end

    #### Error mail
    def send_notification_mail (setting, message)
      smtp_host  = setting['smtp_host']
      smtp_port  = setting['smtp_port']
      to  = setting['to']
      from  = setting['from']

      options = {
        address: smtp_host,
        port: smtp_port
      }
      Mail.defaults do
        delivery_method :smtp, options
      end

      body_text = "An error occurred during the validation process. Please check the following message and log file: #{@log_file}\n\n"
      body_text += message

      mail = Mail.new do
        from     "#{from}"
        to       "#{to.join(", ")}"
        subject  'DDBJ validator API error notification'
        body     "#{body_text}"
      end
      mail.deliver!
    end

    # result.json は web リクエストとこのスレッドが同時に読み書きするため、
    # 部分書き込みを掴ませないよう temp + rename でアトミックに置き換える。
    def atomic_write(path, content)
      tmp = "#{path}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp"
      File.write(tmp, content)
      File.rename(tmp, path)
    end
end
