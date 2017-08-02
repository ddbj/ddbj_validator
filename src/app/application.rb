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
    @@data_dir = File.dirname(__FILE__) +"/../logs" #TODO conf

    configure do
      set :public_folder  , File.expand_path('../../public', __FILE__)
      set :views          , File.expand_path('../views', __FILE__)
      set :root           , File.dirname(__FILE__)
      set :show_exceptions, development?
    end

    configure :development do
      register Sinatra::Reloader
    end

    get '/validation' do
      erb :index
    end

    post '/api/:version/validation' do

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

#       call validator library
        start_time = Time.now
        Validator.new().execute(validation_params)
        p "time: #{Time.now - start_time}s"

        result_json = File.open(output_file_path).read
        json result_json
      else #file 組み合わせエラー
        status 400
        #400
      end
    end

    get '/api/:version/validation/:uuid' do |version, uuid|
      'Requested validation result id:' + uuid
    end

    get '/api/:version/validation/:uuid/:filetype' do |version, uuid, filetype|
      'Requested validation file id:' + uuid + ", filetype:" + filetype
    end

    get '/api/:version/validation/:uuid/:filetype/autocorrect' do |version, uuid, filetype|
      'Requested validation autocorrect id:' + uuid + ", filetype:" + filetype
    end

    get '/api/ubmission' do
      status 400
      headers 'Content-Type' => 'text/plain'
      body 'Bad resuest'
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
