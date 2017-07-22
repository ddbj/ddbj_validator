require 'optparse'
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
      #TODO read setting
    end

    # Executes validation
    # エラーが発生した場合はエラーメッセージを表示して終了する
    # @param [Hash] params {biosample:"XXXX.xml", bioproject:"YYYY.xml", .., output:"ZZZZ.json"}
    # @return [void]
    def execute(params)

      #get absolute file path
      params.each do |k,v|
        case k.to_s
        when 'biosample', 'bioproject', 'experiment', 'run', 'analysis', 'output'
          params[k] = File.expand_path(v)
          #TODO check file exist and permission, need write permission to output file
        end
      end
      p params

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
        #TODO dra validator

        if error_list.size == 0
          ret = {status: "success", format: ARGV[1]}
        else
          ret = {status: "fail", format: ARGV[1], failed_list: error_list}
        end
      rescue => ex
        message = "#{ex.message}"
        message += ex.backtrace.map {|row| row}.join("\n")
        ret = {status: "error", format: ARGV[1], message: message}
      end

      File.open(params[:output], "w") do |file|
        file.puts(JSON.generate(ret))
      end
    end

    def validate(object_type, params)
        begin
          case object_type
          when "biosample"
            validator = BioSampleValidator.new ('private')
            data = params[:biosample]
          when "bioproject"
            validator = BioProjectValidator.new
            data = params[:bioproject]
          end
          validator.validate(data);
          validator.error_list

        rescue => ex
          raise StandardError, ex.message, ex.backtrace
        end
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

    private_class_method :create_command_parser
end
