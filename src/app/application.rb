require 'yaml'
require 'sinatra/base'
require 'sinatra/json'
require "securerandom"
require 'sinatra/reloader'
require File.expand_path('../../lib/validator/validator.rb', __FILE__)

#require_relative "../../ddbj_validator/src/biosample_validator/biosample_validator.rb"
#require_relative  "/" + File.dirname(__FILE__) + "../../../ddbj_validator/src/biosample_validator/biosample_validator.rb" #.rb" # + "../../../src/biosample_validator/biosample_validator.rb"
#require_relative  "../validator/biosample_validator/biosample_validator" #.rb" # + "../../../src/biosample_validator/biosample_validator.rb"
 
module DDBJValidator
  class Application < Sinatra::Base
    setting = YAML.load(File.read(File.dirname(__FILE__) + "/../conf/validator.yml"))
    @@data_dir = setting["api_log"]["path"]
    @@latest_version = setting["version"]["ver"]

    configure do
      set :public_folder  , File.expand_path('../../public', __FILE__)
      set :views          , File.expand_path('../views', __FILE__)
      set :root           , File.dirname(__FILE__)
      set :show_exceptions, development?
    end

    configure :development do
      register Sinatra::Reloader
    end

    get '/api/client/index' do
      erb :index
    end

    #バージョン指定なしの場合、最新バージョンを加えてルーティングを振り分ける
    post '/api/validation' do
      request.path_info.gsub!("/api/validation", "/api/" + @@latest_version + "/validation")
      pass
    end

    get '/api/validation/:uuid' do |uuid|
      request.path_info.gsub!("/api/validation", "/api/" + @@latest_version + "/validation")
      pass
    end

    get '/api/validation/:uuid/status' do |uuid|
      request.path_info.gsub!("/api/validation", "/api/" + @@latest_version + "/validation")
      pass
    end

    get '/api/validation/:uuid/:filetype' do |uuid, filetype|
      request.path_info.gsub!("/api/validation", "/api/" + @@latest_version + "/validation")
      pass
    end

    get '/api/validation/:uuid/:filetype/autocorrect' do |uuid, filetype|
      request.path_info.gsub!("/api/validation", "/api/" + @@latest_version + "/validation")
      pass
    end

    #バージョン指定ありの場合
    post '/api/:version/validation' do |version|
      unless version == @@latest_version #バージョンが最新でなければ400　本当は転送したい
        status 400
      else
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
            status = { uuid: uuid, status: "finished", "start-time": start_time, "end-time": Time.now}
            File.open(status_file_path, "w") do |file|
              file.puts(JSON.generate(status))
            end
          }

          response.headers["Access-Control-Allow-Origin"] = "*"
          content_type :json
          { uuid: uuid }.to_json
        else #file 組み合わせエラー
          status 400
        end
      end
    end

    get '/api/:version/validation/:uuid' do |version, uuid|
      unless version == @@latest_version #バージョンが最新でなければ400　本当は転送したい
        status 400
      else
        save_dir = "#{@@data_dir}/#{uuid[0..1]}/#{uuid}"
        output_file_path = "#{save_dir}/result.json"
        #ファイルがなければ400番?
        result_json = JSON.parse(File.open(output_file_path).read)
        response.headers["Access-Control-Allow-Origin"] = "*"
        content_type :json
        result_json.to_json
      end
    end

    get '/api/:version/validation/:uuid/status' do |version, uuid|
      unless version == @@latest_version #バージョンが最新でなければ400　本当は転送したい
        status 400
      else
        save_dir = "#{@@data_dir}/#{uuid[0..1]}/#{uuid}"
        status_file_path = "#{save_dir}/status.json"
        #ファイルがなければ400番?
        status_json = JSON.parse(File.open(status_file_path).read)
        response.headers["Access-Control-Allow-Origin"] = "*"
        content_type :json
        status_json.to_json
      end
    end

    get '/api/:version/validation/:uuid/:filetype' do |version, uuid, filetype|
      unless version == @@latest_version #バージョンが最新でなければ400　本当は転送したい
        status 400
      else
        save_dir = "#{@@data_dir}/#{uuid[0..1]}/#{uuid}"
        output_file_path = "#{save_dir}/#{filetype}"
        file_list = Dir.glob("#{output_file_path}/*")
        if file_list.size == 1 && File.exist?(file_list.first)
          file_name = File.basename(file_list.first)
          file_path = file_list.first
          response.headers["Access-Control-Allow-Origin"] = "*"
          send_file file_path, :filename => file_name, :type => 'application/xml'
        else
          status 400
        end
      end
    end

    get '/api/:version/validation/:uuid/:filetype/autocorrect' do |version, uuid, filetype|
      unless version == @@latest_version #バージョンが最新でなければ400　本当は転送したい
        status 400
      else
        save_dir = "#{@@data_dir}/#{uuid[0..1]}/#{uuid}"
        output_file_path = "#{save_dir}/result.json"
        response.headers["Access-Control-Allow-Origin"] = "*"
        #TODO filter autocorrect data
      end
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
        req_params = Rack::Utils.parse_query(form_vars)
        param_names = req_params["name"]
        if param_names.instance_of?(Array) #引数1の場合は配列ではなく文字列
          if param_names.select{|name| name == "\"biosample\"" }.size > 1 \
            || param_names.select{|name| name == "\"bioproject\"" }.size > 1 \
            || param_names.select{|name| name == "\"submission\"" }.size > 1 \
            || param_names.select{|name| name == "\"experiment\"" }.size > 1 \
            || param_names.select{|name| name == "\"run\"" }.size > 1 \
            || param_names.select{|name| name == "\"analysis\"" }.size > 1
            file_combination = false
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
    end
  end
end
