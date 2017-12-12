require 'yaml'
require 'sinatra/base'
require 'sinatra/json'
require "securerandom"
require 'sinatra/reloader'
require 'net/http'
require 'net/https'
require File.expand_path('../../lib/validator/validator.rb', __FILE__)
require File.expand_path('../../lib/validator/auto_annotation.rb', __FILE__)
require File.expand_path('../../lib/submitter/submitter.rb', __FILE__)

module DDBJValidator
  class Application < Sinatra::Base
    setting = YAML.load(File.read(File.dirname(__FILE__) + "/../conf/validator.yml"))
    @@data_dir = setting["api_log"]["path"]

    configure do
      set :public_folder  , File.expand_path('../../public', __FILE__)
      set :views          , File.expand_path('../views', __FILE__)
      set :root           , File.dirname(__FILE__)
      set :show_exceptions, development?
    end

    configure :development do
      register Sinatra::Reloader
    end

    before do
      response.headers["Access-Control-Allow-Origin"] = "*"
    end

    head "/" do
      "HEAD"
    end

    get '/api/' do
      send_file File.join(settings.public_folder, 'api/index.html')
    end

    get '/api/apispec/' do
      send_file File.join(settings.public_folder, 'apispec/index.html')
    end

    get '/api/client/index' do
      erb :index
    end

    post '/api/validation' do
      content_type :json
      #組み合わせが成功したものだけ保存しチェック
      if valid_file_combination?

        uuid = SecureRandom.uuid
        save_dir = "#{@@data_dir}/#{uuid[0..1]}/#{uuid}"
        validation_params = {}
        input_file_list = %w(biosample bioproject submission experiment run analysis)
        input_file_list.each do |file_category|
          if params[file_category.to_sym]
            save_path = save_file(save_dir, file_category, params)
            validation_params[file_category.to_sym] = save_path
          end
        end
        output_file_path = "#{save_dir}/result.json"
        validation_params[:output] = output_file_path

        status_file_path = "#{save_dir}/status.json"
        start_time = Time.now
        status = { uuid: uuid, status: "running", "start-time": start_time}
        File.open(status_file_path, "w") do |file|
          file.puts(JSON.generate(status))
        end

        #call validator library
        Thread.new{
          Validator.new().execute(validation_params)
          result_json = JSON.parse(File.open(output_file_path).read)
          if !result_json["status"].nil? && result_json["status"] == "error"
            status = { uuid: uuid, status: "error", "start-time": start_time, "end-time": Time.now}
          else
            status = { uuid: uuid, status: "finished", "start-time": start_time, "end-time": Time.now}
          end
          File.open(status_file_path, "w") do |file|
            file.puts(JSON.generate(status))
          end
        }

        { uuid: uuid, status: "accepted", "start-time": start_time}.to_json
      else #file 組み合わせエラー
        status 400
        message = "Invalid file combination"
        { status: "error", "message": message}.to_json
      end
    end

    get '/api/validation/:uuid' do |uuid|
      content_type :json
      save_dir = "#{@@data_dir}/#{uuid[0..1]}/#{uuid}"
      status_file_path = "#{save_dir}/status.json"
      output_file_path = "#{save_dir}/result.json"
      if File.exist?(output_file_path) && File.exist?(status_file_path)
        result_json = JSON.parse(File.open(output_file_path).read)
        if !result_json["status"].nil? && result_json["status"] == "error"
          status 500
          message = "An error occurred during validation processing."
          { status: "error", "message": message}.to_json
        else
          status_json = JSON.parse(File.open(status_file_path).read)
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
      content_type :json
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
      if file_list.size == 1
        file_name = File.basename(file_list.first)
        file_path = file_list.first
        send_file file_path, :filename => file_name, :type => 'application/xml'
      else
        status 400
        content_type :json
        message = "Invalid uuid or filetype"
        { status: "error", "message": message}.to_json
      end
    end

    get '/api/validation/:uuid/:filetype/autocorrect' do |uuid, filetype|
      save_dir = "#{@@data_dir}/#{uuid[0..1]}/#{uuid}"
      result_file = "#{save_dir}/result.json"
      org_file_list = Dir.glob("#{save_dir}/#{filetype}/*")
      annotated_file_path = ""
      if File.exist?(result_file) && org_file_list.size == 1
        org_file = org_file_list.first
        annotated_file_name = File.basename(org_file, ".*") + "_annotated" + File.extname(org_file)
        annotated_file_dir = "#{save_dir}/autoannotated/#{filetype}"
        FileUtils.mkdir_p(annotated_file_dir)
        annotated_file_path = "#{annotated_file_dir}/#{annotated_file_name}"
        AutoAnnotation.new().create_annotated_file(org_file, result_file, annotated_file_path, filetype)
      end
      if File.exist?(annotated_file_path)
        send_file annotated_file_path, :filename => annotated_file_name, :type => 'application/xml'
      else
        status 400
        content_type :json
        message = "Invalid uuid or filetype, or the auto-correct data is not exist of the uuid specified"
        { status: "error", "message": message}.to_json
      end
    end

    get '/api/submission/:filetype/:submittion_id' do |filetype, submission_id|
      headers = request.env.select do |key, val|
        key.start_with?("HTTP_")
      end
      if headers["HTTP_API_KEY"].nil? || headers["HTTP_API_KEY"] != "curator" #TODO change
        status 401
        content_type :json
        message = "Unauthorized. Please input authorication information"
        { status: "error", "message": message}.to_json
      else
        uuid = SecureRandom.uuid
        save_dir = "#{@@data_dir}/submission_xml/#{uuid[0..1]}/#{uuid}"
        FileUtils.mkdir_p(save_dir)
        ret = Submitter.new().submission_xml(filetype, submission_id, save_dir)
        if ret[:status] == "success"
          send_file ret[:file_path], :filename => File.basename(ret[:file_path]), :type => 'application/xml'
        elsif ret[:status] == "fail"
          status 400
          content_type :json
          message = "Invalid filetype or submission_id"
          { status: "error", "message": message}.to_json
        elsif ret[:status] == "error"
          status 500
          content_type :json
          message = "An error occurred during processing."
          { status: "error", "message": message}.to_json
        end
      end
    end

    get '/api/monitoring' do
      ret_message = ""
      submission_id = "SSUB000019"
      begin
        # api url path
p request.env
p request
        api_url = "http://" + request.env["HTTP_HOST"] + "/api/"
puts api_url
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
      rescue => e
        ret_message = '{"status": "NG", "message": "Error has occurred during monitoring processing. Please check the validation service. ' + e.message + '"}'
      end
      ret_message
    end

    not_found do
      erb :not_found
    end

    helpers do
      # file数と組み合わせをチェック
      def valid_file_combination?
        # paramsでは重複を省いたrequest parameterで渡されるため、form_inputで全データ確認する
        file_combination = true
        form_vars = @env["rack.request.form_input"].read
        Rack::Utils.key_space_limit = 10000000
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

      #file保存を保存し、ファイルパスを返す
      def save_file (output_dir, validator_type, params)
        save_dir = "#{output_dir}/#{validator_type}"
        FileUtils.mkdir_p(save_dir)
        save_path = save_dir + "/" + params[validator_type.to_sym][:filename]
        File.open(save_path, 'wb') do |f|
          f.write params[validator_type.to_sym][:tempfile].read
        end
        save_path
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
