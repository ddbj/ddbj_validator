require 'yaml'
require 'sinatra/base'
require 'sinatra/json'
require "securerandom"
require 'sinatra/reloader'
require 'net/http'
require 'net/https'
require 'fileutils'
require File.expand_path('../../lib/validator/validator.rb', __FILE__)
require File.expand_path('../../lib/validator/biosample_validator.rb', __FILE__)
require File.expand_path('../../lib/validator/auto_annotator/auto_annotator.rb', __FILE__)
require File.expand_path('../../lib/submitter/submitter.rb', __FILE__)
require File.expand_path('../../lib/package/package.rb', __FILE__)

module DDBJValidator
  class Application < Sinatra::Base
    setting = YAML.load(ERB.new(File.read(File.dirname(__FILE__) + "/../conf/validator.yml")).result)
    @@data_dir = setting["api_log"]["path"]
    @@biosample_package_version = BioSampleValidator::DEFAULT_PACKAGE_VERSION

    configure do
      set :public_folder  , File.expand_path('../../public', __FILE__)
      set :views          , File.expand_path('../views', __FILE__)
      set :root           , File.dirname(__FILE__)
      set :show_exceptions, development?
    end

    before do
      content_type 'application/json; charset=utf-8'
      response.headers["Access-Control-Allow-Origin"] = "*"
    end

    head "/" do
      "HEAD"
    end

    get '/api/' do
      content_type 'text/html; charset=utf-8'
      send_file File.join(settings.public_folder, 'api/index.html')
    end

    get '/api/apispec/' do
      content_type 'text/html; charset=utf-8'
      send_file File.join(settings.public_folder, 'api/apispec/index.html')
    end

    get '/api/client/index' do
      content_type 'text/html; charset=utf-8'
      erb :index
    end

    post '/api/validation' do
      #組み合わせが成功したものだけ保存しチェック
      if valid_file_combination?

        uuid = SecureRandom.uuid
        save_dir = "#{@@data_dir}/#{uuid[0..1]}/#{uuid}"
        validation_params = {}
        input_file_list = %w(all_db biosample bioproject submission experiment run analysisx jvar vcf trad_anno trad_seq trad_agp metabobank_idf metabobank_sdrf)
        input_file_list.each do |file_category|
          if params[file_category.to_sym]
            save_path = save_file(save_dir, file_category, params)
            validation_params[file_category.to_sym] = save_path
          end
        end
        allow_params = %w(submitter_id biosample_submission_id bioproject_submission_id check_sheet check_sheet[])
        validation_params[:params] = {}
        allow_params.each do |param_name|
          if params[param_name.to_sym]
            validation_params[:params][param_name] = params[param_name.to_sym]
          end
        end

        output_file_path = "#{save_dir}/result.json"
        validation_params[:output] = output_file_path

        status_file_path = "#{save_dir}/status.json"
        start_time = Time.now
        status = { uuid: uuid, status: "running", "start_time": start_time}
        File.open(status_file_path, "w") do |file|
          file.puts(JSON.generate(status))
        end

        #call validator library
        Thread.new{
          Validator.new().execute(validation_params)
          result_json = JSON.parse(File.open(output_file_path).read)
          if !result_json["status"].nil? && result_json["status"] == "error"
            status = { uuid: uuid, status: "error", "start_time": start_time, "end_time": Time.now}
          else
            status = { uuid: uuid, status: "finished", "start_time": start_time, "end_time": Time.now}
          end
          File.open(status_file_path, "w") do |file|
            file.puts(JSON.generate(status))
          end
        }

        { uuid: uuid, status: "accepted", "start_time": start_time}.to_json
      else #file 組み合わせエラー
        status 400
        message = "Invalid file combination"
        { status: "error", "message": message}.to_json
      end
    end

    get '/api/validation/:uuid' do |uuid|
      save_dir = "#{@@data_dir}/#{uuid[0..1]}/#{uuid}"
      status_file_path = "#{save_dir}/status.json"
      output_file_path = "#{save_dir}/result.json"
      if File.exist?(output_file_path) && File.exist?(status_file_path)
        result_json = JSON.parse(File.open(output_file_path).read)
        if !result_json["status"].nil? && result_json["status"] == "error"
          status 500
        else
          status_json = JSON.parse(File.open(status_file_path).read)
          if params.keys.include?("grouped_messages")
            result_json = Validator.new().grouped_message(result_json)
          end
          status_json["result"] = result_json
          status_json.to_json
        end
      else
        if File.exist?(status_file_path) && JSON.parse(File.open(status_file_path).read)["status"] == "running"
          message = "Validation process has not finished yet"
        else
          message = "Invalid uuid"
        end
        status 400
        { status: "error", "message": message}.to_json
      end
    end

    get '/api/validation/:uuid/status' do |uuid|
      save_dir = "#{@@data_dir}/#{uuid[0..1]}/#{uuid}"
      status_file_path = "#{save_dir}/status.json"
      if File.exist?(status_file_path)
        status_json = JSON.parse(File.open(status_file_path).read)
        status_json.to_json
      else
        status 400
        message = "Invalid uuid"
        { status: "error", "message": message}.to_json
      end
    end

    get '/api/validation/:uuid/:filetype' do |uuid, filetype|
      save_dir = "#{@@data_dir}/#{uuid[0..1]}/#{uuid}"
      file_list = Dir.glob("#{save_dir}/#{filetype}/*")
      if filetype == 'jvar' #jvarは元ファイルがExcelだが変換したJSONを返して欲しいケースを想定 TODO コードが長い
        if get_accept_header(request).include?("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
          file = file_list.select{|file| file.end_with?(".xlsx")} # TODO ファイル拡張子があるとは限らない
          type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        else
          file = file_list.select{|file| file.end_with?(".json")} #変換できなかった場合はこのファイルは無い
          type = "application/json"
        end
        if file.size == 0
          status 400
          message = "Invalid uuid or filetype"
          { status: "error", "message": message}.to_json
        else
          file_name = File.basename(file.first)
          file_path = file.first
          send_file file_path, :filename => file_name, :type => type
        end
      elsif file_list.size == 1
        file_name = File.basename(file_list.first)
        file_path = file_list.first
        send_file file_path, :filename => file_name, :type => 'application/xml'
      else
        status 400
        message = "Invalid uuid or filetype"
        { status: "error", "message": message}.to_json
      end
    end

    get '/api/validation/:uuid/:filetype/autocorrect' do |uuid, filetype|
      save_dir = "#{@@data_dir}/#{uuid[0..1]}/#{uuid}"
      result_file = "#{save_dir}/result.json"
      org_file_list = Dir.glob("#{save_dir}/#{filetype}/*")
      annotated_file_path = ""
      result = nil
      if File.exist?(result_file) && org_file_list.size == 1
        org_file = org_file_list.first
        annotated_file_name = File.basename(org_file, ".*") + "_annotated" + File.extname(org_file)
        annotated_file_dir = "#{save_dir}/autoannotated/#{filetype}"
        FileUtils.mkdir_p(annotated_file_dir)
        annotated_file_path = "#{annotated_file_dir}/#{annotated_file_name}"
        result = AutoAnnotator.new().create_annotated_file(org_file, result_file, annotated_file_path, filetype, get_accept_header(request))
        if result.nil? || result[:status].nil? ||  result[:status] != "succeed" # 処理が成功しなかった
          status 500
          { status: "error", "message": result[:message]}.to_json
        else #成功した場合、出力ファイルのContent-typeで返す
          if result[:file_type] == "json"
            type = "application/json"
          elsif result[:file_type] == "tsv"
            type = "text/tab-separated-values"
          else
            type = "application/xml"
          end
          send_file result[:file_path], :filename => File.basename(result[:file_path]), :type => type
        end
      else #元ファイルがない
        status 400
        message = "Invalid uuid or filetype, or the auto-correct data is not exist of the uuid specified"
        return { status: "error", "message": message}.to_json
      end
    end

    get '/api/submission/ids/:filetype' do |filetype|
      headers = request.env.select do |key, val|
        key.start_with?("HTTP_")
      end
      if headers["HTTP_API_KEY"].nil? || headers["HTTP_API_KEY"] != "curator" #TODO change
        status 401
      else
        ret = Submitter.new().submission_id_list(filetype)
        if ret[:status] == "success"
          ret[:data].to_json
        elsif ret[:status] == "fail"
          status 400
          message = "Invalid filetype"
          { status: "error", "message": message}.to_json
        elsif ret[:status] == "error"
          status 500
        end
      end
    end

    get '/api/submission/:filetype/:submittion_id' do |filetype, submission_id|
      headers = request.env.select do |key, val|
        key.start_with?("HTTP_")
      end
      if headers["HTTP_API_KEY"].nil? || headers["HTTP_API_KEY"] != "curator" #TODO change
        status 401
      else
        uuid = SecureRandom.uuid
        save_dir = "#{@@data_dir}/submission_xml/#{uuid[0..1]}/#{uuid}"
        FileUtils.mkdir_p(save_dir)
        ret = Submitter.new().submission_xml(filetype, submission_id, save_dir)
        if ret[:status] == "success"
          send_file ret[:file_path], :filename => File.basename(ret[:file_path]), :type => 'application/xml'
        elsif ret[:status] == "fail"
          status 400
          message = "Invalid filetype or submission_id"
          { status: "error", "message": message}.to_json
        elsif ret[:status] == "error"
          status 500
        end
      end
    end

    get '/api/monitoring' do
      ret_message = ""

      begin
        # test data
        unless setting["monitoring"]["ssub_id"].nil?
          submission_id = setting["monitoring"]["ssub_id"]
        else
          submission_id = "SSUB009526"
        end
        local_port = ENV.fetch("DDBJ_VALIDATOR_APP_UNICORN_PORT")
        # api url path
        api_url = "http://localhost:#{local_port}/api/"
        # get xml file
        file_get_api = api_url + "submission/biosample/" + submission_id
        res = http_get_response(file_get_api, {"API_KEY" => "curator"})
        unless res.body.start_with?("<?xml")
          raise "Can't get submission xml file. Please check the validation service."
        end
        tmp_xml_file = Tempfile.open("test_biosample") do |f|
          f.puts(res.body)
          f
        end
        # exec validation
        validate_exec_api = api_url + "validation"
        data = [
          [ "biosample", tmp_xml_file.open, { filename: submission_id + ".xml" } ]
        ]
        res = http_post_response(validate_exec_api, data , {})
        uuid = JSON.parse(res.body)["uuid"]
        # wait validator has finished
        status_api = api_url + "validation/" + uuid + "/status"
        status = ""
        count = 0
        while !(status == "finished" || status == "error") do
          count += 1
          res = http_get_response(status_api, {})
          status = JSON.parse(res.body)["status"]
          if count > 50 #timeout
            raise "Validation processing timed out."
          end
          sleep(2)
        end
        # get validation result
        result_api = api_url + "validation/" + uuid
        res = http_get_response(result_api, {})
        status = JSON.parse(res.body)["status"]

        if status == "finished"
          ret_message = '{"status": "OK", "message": "Validation processing has finished successfully."}'
        else
          ret_message =  '{"status": "NG", "message": "Validation processing finished with error. Please check the validation service."}'
        end
        save_dir = "#{@@data_dir}/#{uuid[0..1]}/#{uuid}"
        FileUtils.rm_r(save_dir)
      rescue => e
        ret_message = '{"status": "NG", "message": "Error has occurred during monitoring processing. Please check the validation service. ' + e.message + '"}'
      end
      ret_message
    end

    # package関連
    get '/api/package_list' do
      version = params["version"]
      if params["version"].nil? || params["version"].strip == ""
        version = @@biosample_package_version
      end
      ret = Package.new(setting["sparql_endpoint"]["master_endpoint"]).package_list(version)
      if ret[:status] == "success"
        ret[:data].to_json
      elsif ret[:status] == "fail"
        status 400
        {"status": "error", "message": ret[:message]}.to_json
      else # error
        status 500
        {"status": "error", "message": ret[:message]}.to_json
      end
    end

    get '/api/package_and_group_list' do
      version = params["version"]
      if params["version"].nil? || params["version"].strip == ""
        version = @@biosample_package_version
      end
      ret = Package.new(setting["sparql_endpoint"]["master_endpoint"]).package_and_group_list(version)
      if ret[:status] == "success"
        ret[:data].to_json
      elsif ret[:status] == "fail"
        status 400
        {"status": "error", "message": ret[:message]}.to_json
      else # error
        status 500
        {"status": "error", "message": ret[:message]}.to_json
      end
    end

    get '/api/attribute_list' do
      if params["package"].nil? || params["package"].strip == ""
        status 400
        message = "'package' parameter is required"
        ret = { status: "error", "message": message}.to_json
        return ret
      end
      version = params["version"]
      if params["version"].nil? || params["version"].strip == ""
        version = @@biosample_package_version
      end
      ret = Package.new(setting["sparql_endpoint"]["master_endpoint"]).attribute_list(version, params["package"])
      if ret[:status] == "success"
        ret[:data].to_json
      elsif ret[:status] == "fail"
        status 400
        {"status": "error", "message": ret[:message]}.to_json
      else # error
        status 500
        {"status": "error", "message": ret[:message]}.to_json
      end
    end

    get '/api/attribute_template_file' do
      if params["package"].nil? || params["package"].strip == ""
        status 400
        message = "'package' parameter is required"
        ret = { status: "error", "message": message}.to_json
        return ret
      end
      version = params["version"]
      if params["version"].nil? || params["version"].strip == ""
        version = @@biosample_package_version
      end
      only_biosample_sheet = false
      if params["only_biosample_sheet"]
        only_biosample_sheet = true
      end
      ret = Package.new(nil).attribute_template_file(version, params["package"], only_biosample_sheet, get_accept_header(request))
      if ret[:status] == "success"
        if ret[:file_type] == "tsv"
          type = "text/tab-separated-values"
          file_name = "template.tsv"
        else
          type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          file_name = "template.xlsx"
        end
        send_file ret[:file_path], :filename => file_name, :type => type
      elsif ret[:status] == "fail"
        status 400
        {"status": "error", "message": ret[:message]}.to_json
      else # error
        status 500
        {"status": "error", "message": ret[:message]}.to_json
      end
    end

    get '/api/package_info' do
      if params["package"].nil? || params["package"].strip == ""
        status 400
        message = "'package' parameter is required"
        ret = { status: "error", "message": message}.to_json
        return ret
      end
      version = params["version"]
      if params["version"].nil? || params["version"].strip == ""
        version = @@biosample_package_version
      end
      ret = Package.new(setting["sparql_endpoint"]["master_endpoint"]).package_info(version, params["package"])
      if ret[:status] == "success"
        ret[:data].to_json
      elsif ret[:status] == "fail"
        status 400
        {"status": "error", "message": ret[:message]}.to_json
      else # error
        status 500
        {"status": "error", "message": ret[:message]}.to_json
      end
    end

    #error response
    error 400..599 do
      if status == 400 #400番の場合は詳細メッセージを表示するために、設定されたresponseをそのまま返す
        response
      elsif status == 401
        send_file(File.join(settings.public_folder, 'error_unauthorized.json'), {status: 401})
      elsif status == 403
        send_file(File.join(settings.public_folder, 'error_forbidden.json'), {status: 403})
      elsif status == 404
        send_file(File.join(settings.public_folder, 'error_not_found.json'), {status: 404})
      elsif status == 500
        send_file(File.join(settings.public_folder, 'error_internal_server_error.json'), {status: 500})
      else #other error with rack default message
        { status: "error", "message": Rack::Utils::HTTP_STATUS_CODES[status] }.to_json
      end
    end

    # error content for statis url
    get '/api/error_unauthorized.json' do
      401
    end
    get '/api/error_forbidden.json' do
      403
    end
    get '/api/error_not_found.json' do
      404
    end


    helpers do
      # file数と組み合わせをチェック
      def valid_file_combination?
        # paramsでは重複を省いたrequest parameterで渡されるため、form_inputで全データ確認する
        file_combination = true
        form_vars = @env["rack.request.form_input"].read
        Rack::Utils.key_space_limit = 100000000
        form_vars = Rack::Utils.escape(form_vars)
        req_params = Rack::Utils.parse_query(form_vars)
        param_names = req_params["name"]
        if param_names.instance_of?(Array) #引数1の場合は配列ではなく文字列
          #同じfiletypeで複数ファイルが送られて来た場合はエラー
          if param_names.select{|name| name == "\"biosample\"" }.size > 1 \
            || param_names.select{|name| name == "\"bioproject\"" }.size > 1 \
            || param_names.select{|name| name == "\"submission\"" }.size > 1 \
            || param_names.select{|name| name == "\"experiment\"" }.size > 1 \
            || param_names.select{|name| name == "\"run\"" }.size > 1 \
            || param_names.select{|name| name == "\"analysis\"" }.size > 1
            file_combination = false
          end

          #DRAファイルが送信された場合、"submission", "experiment", "run"のセットは必須。"analysis"は任意
          sent_filetype = params.keys #実際にファイル選択されて送られてきたfiletype
          dra_filetype_list = ["submission", "experiment", "run", "analysis"]
          if dra_filetype_list.any? {|dra_filetype| sent_filetype.include?(dra_filetype)}
            unless (sent_filetype.include?("submission") \
               && sent_filetype.include?("experiment") \
               && sent_filetype.include?("run"))
               file_combination = false
            end
          end
        end
        file_combination
      end

      #fileを保存し、ファイルパスを返す
      def save_file (output_dir, validator_type, params)
        save_dir = "#{output_dir}/#{validator_type}"
        FileUtils.mkdir_p(save_dir)
        if params[validator_type.to_sym].is_a?(String) #fileではなくデータで送られた場合
          save_path = save_dir + "/#{validator_type}" #ファイル名はデータの種類名("biosample"等)
          File.open(save_path, 'wb') do |f|
            f.write params[validator_type.to_sym]
          end
        else
          save_path = save_dir + "/" + params[validator_type.to_sym][:filename]
          File.open(save_path, 'wb') do |f|
            f.write params[validator_type.to_sym][:tempfile].read
          end
        end
        save_path
      end

      # Acceptヘッダーをリストで返す
      def get_accept_header(request)
        accept = request.env.select { |k, v| k.start_with?('HTTP_ACCEPT') }
        if accept.size == 0
          []
        else
          accept
        end
      end

      def http_get_response (uri, options)
        url = URI.parse(uri)
        req = Net::HTTP::Get.new(url)
        options.each do |k, v|
          req[k] = v
        end
        ssl_flag = false
        ssl_flag = true if uri.start_with?("https")
        res = Net::HTTP.start(url.host, url.port, :use_ssl => ssl_flag) {|http|
          http.request(req)
        }
        res
      end

      def http_post_response (uri, data, options)
        url = URI.parse(uri)
        req = Net::HTTP::Post.new(url)
        req.set_form(data, "multipart/form-data")
        options.each do |k, v|
          req[k] = v
        end
        ssl_flag = false
        ssl_flag = true if uri.start_with?("https")
        res = Net::HTTP.start(url.host, url.port, :use_ssl => ssl_flag) {|http|
          http.request(req)
        }
        res
      end

    end

  end
end
