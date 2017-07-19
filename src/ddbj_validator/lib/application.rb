require 'sinatra/base'
require 'sinatra/json'
require "securerandom"
require 'sinatra/reloader'
require File.expand_path('../validator/validator.rb', __FILE__)

#require_relative "../../ddbj_validator/src/biosample_validator/biosample_validator.rb"
#require_relative  "/" + File.dirname(__FILE__) + "../../../ddbj_validator/src/biosample_validator/biosample_validator.rb" #.rb" # + "../../../src/biosample_validator/biosample_validator.rb"
#require_relative  "../validator/biosample_validator/biosample_validator" #.rb" # + "../../../src/biosample_validator/biosample_validator.rb"
 
module DDBJValidator
  class Application < Sinatra::Base
    @@data_dir = File.dirname(__FILE__) +"/../logs" #TODO conf

    configure do
      set :public_folder  , File.expand_path('../public', __FILE__)
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

        if params[:biosample]
          uuid = SecureRandom.uuid
          save_dir = "#{@@data_dir}/#{uuid}/biosample"
          FileUtils.mkdir_p(save_dir)
          save_path = save_dir + "/" + params[:biosample][:filename]
          File.open(save_path, 'wb') do |f|
            f.write params[:biosample][:tempfile].read
          end
          start_time = Time.now
          output_file_path = "#{@@data_dir}/#{uuid}/result.json"

#         call validator library
          validation_params = {biosample: save_path, output: output_file_path }
          Validator.new().execute(validation_params)

          Dir.chdir("./lib/validator/biosample_validator") {
            system("ruby biosample_validator.rb #{save_path} xml #{output_file_path} private")
          }
          p "time: #{Time.now - start_time}s"
          result_json = File.open(output_file_path).read
          json result_json         
        end
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
    end
  end
end
