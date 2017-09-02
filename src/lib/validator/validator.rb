require 'optparse'
require 'logger'
require 'yaml'
require 'mail'

require File.expand_path('../biosample_validator.rb', __FILE__)
require File.expand_path('../bioproject_validator.rb', __FILE__)

# Validator main class
class Validator

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
      @setting = YAML.load(File.read(config_file_dir + "/validator.yml"))
      @log_file = @setting["api_log"]["path"] + "validator.log"
      @log = Logger.new(@log_file)
    end

    # Executes validation
    # エラーが発生した場合はエラーメッセージを表示して終了する
    # @param [Hash] params {biosample:"XXXX.xml", bioproject:"YYYY.xml", .., output:"ZZZZ.json"}
    # @return [void]
    def execute(params)
      @log.info('execute validation:' + params.to_s)

      #get absolute file path and check permission
      permission_error_list = []
      params.each do |k,v|
        case k.to_s
        when 'biosample', 'bioproject', 'submision', 'experiment', 'run', 'analysis', 'output'
          params[k] = File.expand_path(v)
          #TODO check file exist and permission, need write permission to output file
          if k.to_s == 'output'
            dir_path = File.dirname(params[k])
            unless File.writable? dir_path
              permission_error_list.push(dir_path)
            end
          else
            unless File.readable? params[k]
              permission_error_list.push(params[k])
            end
          end
        end
      end
      if permission_error_list.size > 0
        ret = {status: "error", format: ARGV[1], message: "permision error: #{permission_error_list.join(', ')}"}
        JSON.generate(ret)
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
      begin
        ret = {}
        error_list = []
        error_list.concat(validate("biosample", params)) if !params[:biosample].nil?
        error_list.concat(validate("bioproject", params))if !params[:bioproject].nil?
        #error_list.concat(validate("combination", params))
        #TODO dra validator

        if error_list.size == 0
          ret = {status: "success", format: ARGV[1]}
          @log.info('validation result: ' + "success")
        else
          ret = {status: "fail", format: ARGV[1], failed_list: error_list}
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

        ret = {status: "error", format: ARGV[1], message: ex.message}
      end

      File.open(params[:output], "w") do |file|
        file.puts(JSON.generate(ret))
      end
      JSON.generate(ret)
    end

    def validate(object_type, params)
      case object_type
      when "biosample"
        validator = BioSampleValidator.new
        data = params[:biosample]
      when "bioproject"
        validator = BioProjectValidator.new
        data = params[:bioproject]
      when "combination"
        validator = CombinationValidator.new
        data = params
      end
      validator.validate(data);
      validator.error_list
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
