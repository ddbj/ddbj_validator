require 'net/http'
require 'net/https'
require 'securerandom'
require 'tempfile'

class ApiController < ApplicationController
  # --- static ---

  def index
    send_file Rails.public_path.join('api/index.html'), type: 'text/html', disposition: 'inline'
  end

  def apispec
    send_file Rails.public_path.join('api/apispec/index.html'), type: 'text/html', disposition: 'inline'
  end

  # 旧 Sinatra 版の `erb :index` を生成結果ファイルの送付に置き換え。
  def client
    send_file Rails.public_path.join('api/client/index.html'), type: 'text/html', disposition: 'inline'
  end

  def error_unauthorized
    send_file Rails.public_path.join('error_unauthorized.json'), type: 'application/json', disposition: 'inline', status: :unauthorized
  end

  def error_forbidden
    send_file Rails.public_path.join('error_forbidden.json'), type: 'application/json', disposition: 'inline', status: :forbidden
  end

  def error_not_found
    send_file Rails.public_path.join('error_not_found.json'), type: 'application/json', disposition: 'inline', status: :not_found
  end

  # --- validation ---

  def validation_create
    unless valid_file_combination?
      render_error('Invalid file combination', status: :bad_request)
      return
    end

    uuid       = SecureRandom.uuid
    save_dir   = File.join(data_dir, uuid[0..1], uuid)
    start_time = Time.now

    FileUtils.mkpath(save_dir)

    validation_params = {params: {'file_format' => {}}}

    %w[all_db biosample bioproject submission experiment run analysisx jvar trad_anno trad_seq trad_agp metabobank_idf metabobank_sdrf].each do |category|
      next unless params[category]

      validation_params[category.to_sym]               = save_uploaded_file(save_dir, category)
      validation_params[:params]['file_format'][category] = detect_file_format(category) if detect_file_format(category)
    end

    %w[submitter_id biosample_submission_id bioproject_submission_id check_sheet check_sheet[]].each do |name|
      validation_params[:params][name] = params[name] if params[name]
    end

    output_file_path = File.join(save_dir, 'result.json')
    status_file_path = File.join(save_dir, 'status.json')
    validation_params[:output] = output_file_path

    write_status_file(status_file_path, {uuid: uuid, status: 'running', start_time: start_time})

    Thread.new {
      Validator.new.execute(validation_params)
      result = JSON.parse(File.read(output_file_path))
      final  = result['status'] == 'error' ? 'error' : 'finished'
      write_status_file(status_file_path, {uuid: uuid, status: final, start_time: start_time, end_time: Time.now})
    }

    render json: {uuid: uuid, status: 'accepted', start_time: start_time}
  end

  def validation_show
    save_dir         = File.join(data_dir, params[:uuid][0..1], params[:uuid])
    status_file_path = File.join(save_dir, 'status.json')
    output_file_path = File.join(save_dir, 'result.json')

    if File.exist?(output_file_path) && File.exist?(status_file_path)
      result = JSON.parse(File.read(output_file_path))

      if result['status'] == 'error'
        head :internal_server_error
      else
        status_json = JSON.parse(File.read(status_file_path))
        result      = Validator.new.grouped_message(result) if params.key?('grouped_messages')

        render json: status_json.merge('result' => result)
      end
    else
      message =
        if File.exist?(status_file_path) && JSON.parse(File.read(status_file_path))['status'] == 'running'
          'Validation process has not finished yet'
        else
          'Invalid uuid'
        end

      render_error(message, status: :bad_request)
    end
  end

  def validation_status
    status_file_path = File.join(data_dir, params[:uuid][0..1], params[:uuid], 'status.json')

    if File.exist?(status_file_path)
      send_file status_file_path, type: 'application/json', disposition: 'inline'
    else
      render_error('Invalid uuid', status: :bad_request)
    end
  end

  def validation_file
    save_dir  = File.join(data_dir, params[:uuid][0..1], params[:uuid])
    file_list = Dir.glob(File.join(save_dir, params[:filetype], '*'))

    if params[:filetype] == 'jvar'
      if accept_header.to_s.include?('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
        file = file_list.find {|f| f.end_with?('.xlsx') }
        type = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      else
        file = file_list.find {|f| f.end_with?('.json') }
        type = 'application/json'
      end

      if file.nil?
        render_error('Invalid uuid or filetype', status: :bad_request)
      else
        send_file file, filename: File.basename(file), type: type
      end
    elsif file_list.size == 1
      send_file file_list.first, filename: File.basename(file_list.first), type: 'application/xml'
    else
      render_error('Invalid uuid or filetype', status: :bad_request)
    end
  end

  def validation_autocorrect
    save_dir      = File.join(data_dir, params[:uuid][0..1], params[:uuid])
    result_file   = File.join(save_dir, 'result.json')
    org_file_list = Dir.glob(File.join(save_dir, params[:filetype], '*'))

    unless File.exist?(result_file) && org_file_list.size == 1
      render_error('Invalid uuid or filetype, or the auto-correct data is not exist of the uuid specified', status: :bad_request)
      return
    end

    org_file            = org_file_list.first
    annotated_file_dir  = File.join(save_dir, 'autoannotated', params[:filetype])
    annotated_file_name = "#{File.basename(org_file, '.*')}_annotated#{File.extname(org_file)}"
    annotated_file_path = File.join(annotated_file_dir, annotated_file_name)

    FileUtils.mkdir_p(annotated_file_dir)

    result = AutoAnnotator.new.create_annotated_file(org_file, result_file, annotated_file_path, params[:filetype], accept_header)

    if result.nil? || result[:status] != 'succeed'
      render json: {status: 'error', message: result && result[:message]}, status: :internal_server_error
    else
      type =
        case result[:file_type]
        when 'json' then 'application/json'
        when 'tsv'  then 'text/tab-separated-values'
        else 'application/xml'
        end

      send_file result[:file_path], filename: File.basename(result[:file_path]), type: type
    end
  end

  # --- submission ---

  def submission_ids
    return unless authenticate_curator

    ret = Submitter.new.submission_id_list(params[:filetype])

    case ret[:status]
    when 'success' then render json: ret[:data]
    when 'fail'    then render_error('Invalid filetype', status: :bad_request)
    else                head :internal_server_error
    end
  end

  def submission_show
    return unless authenticate_curator

    uuid     = SecureRandom.uuid
    save_dir = File.join(data_dir, 'submission_xml', uuid[0..1], uuid)

    FileUtils.mkdir_p(save_dir)

    ret = Submitter.new.submission_xml(params[:filetype], params[:submission_id], save_dir)

    case ret[:status]
    when 'success' then send_file ret[:file_path], filename: File.basename(ret[:file_path]), type: 'application/xml'
    when 'fail'    then render_error('Invalid filetype or submission_id', status: :bad_request)
    else                head :internal_server_error
    end
  end

  # --- monitoring ---

  # 本番 deploy 時の生存確認。biosample の実 validation を 1 サイクル回す。
  # NG のときは HTTP 503 で返すことで curl --fail probe を失敗させる。
  def monitoring
    submission_id = validator_setting.dig('monitoring', 'ssub_id') || 'SSUB009526'
    local_port    = ENV.fetch('DDBJ_VALIDATOR_APP_UNICORN_PORT', '3000')
    api_url       = "http://localhost:#{local_port}/api/"

    res = http_get_response(api_url + "submission/biosample/#{submission_id}", 'API_KEY' => 'curator')
    raise "Can't get submission xml file. Please check the validation service." unless res.body.start_with?('<?xml')

    tmp_xml_file = Tempfile.open('test_biosample') {|f|
      f.puts(res.body)
      f
    }

    post_data = [['biosample', tmp_xml_file.open, {filename: "#{submission_id}.xml"}]]
    res       = http_post_response(api_url + 'validation', post_data)
    uuid      = JSON.parse(res.body)['uuid']

    status = ''
    count  = 0

    until %w[finished error].include?(status)
      count += 1
      res    = http_get_response(api_url + "validation/#{uuid}/status")
      status = JSON.parse(res.body)['status']

      raise 'Validation processing timed out.' if count > 50

      sleep(2)
    end

    res           = http_get_response(api_url + "validation/#{uuid}")
    final_status  = JSON.parse(res.body)['status']
    FileUtils.rm_rf(File.join(data_dir, uuid[0..1], uuid))

    if final_status == 'finished'
      render json: {status: 'OK', message: 'Validation processing has finished successfully.'}
    else
      render json: {status: 'NG', message: 'Validation processing finished with error. Please check the validation service.'},
             status: :service_unavailable
    end
  rescue => e
    render json: {status: 'NG', message: "Error has occurred during monitoring processing. Please check the validation service. #{e.message}"},
           status: :service_unavailable
  end

  # --- packages ---

  def package_list
    ret = Package.new(validator_setting['sparql_endpoint']['master_endpoint']).package_list(requested_package_version)
    render_package_result(ret)
  end

  def package_and_group_list
    ret = Package.new(validator_setting['sparql_endpoint']['master_endpoint']).package_and_group_list(requested_package_version)
    render_package_result(ret)
  end

  def attribute_list
    if params[:package].blank?
      render_error("'package' parameter is required", status: :bad_request)
      return
    end

    ret = Package.new(validator_setting['sparql_endpoint']['master_endpoint']).attribute_list(requested_package_version, params[:package])
    render_package_result(ret)
  end

  def attribute_template_file
    if params[:package].blank?
      render_error("'package' parameter is required", status: :bad_request)
      return
    end

    ret = Package.new(nil).attribute_template_file(requested_package_version, params[:package], params[:only_biosample_sheet].present?, accept_header)

    case ret[:status]
    when 'success'
      if ret[:file_type] == 'tsv'
        send_file ret[:file_path], filename: 'template.tsv', type: 'text/tab-separated-values'
      else
        send_file ret[:file_path], filename: 'template.xlsx', type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      end
    when 'fail' then render_error(ret[:message], status: :bad_request)
    else             render_error(ret[:message], status: :internal_server_error)
    end
  end

  def package_info
    if params[:package].blank?
      render_error("'package' parameter is required", status: :bad_request)
      return
    end

    ret = Package.new(validator_setting['sparql_endpoint']['master_endpoint']).package_info(requested_package_version, params[:package])
    render_package_result(ret)
  end

  private

  # request.headers['API_KEY'] は underscore を含むキーを HTTP_ プレフィックス変換
  # しないため env を直接参照する。旧 Sinatra 版の headers["HTTP_API_KEY"] と互換。
  def authenticate_curator
    return true if request.env['HTTP_API_KEY'] == 'curator'

    send_file Rails.public_path.join('error_unauthorized.json'),
              type: 'application/json', disposition: 'inline', status: :unauthorized
    false
  end

  def requested_package_version
    params[:version].presence || biosample_package_version
  end

  def render_package_result (ret)
    case ret[:status]
    when 'success' then render json: ret[:data]
    when 'fail'    then render json: {status: 'error', message: ret[:message]}, status: :bad_request
    else                render json: {status: 'error', message: ret[:message]}, status: :internal_server_error
    end
  end

  # Rack 3 で rack.request.form_input は multipart 時でも nil になり得るため、
  # rack.input から直接読んで name フィールドの重複とセット要件をチェックする。
  def valid_file_combination?
    input = request.env['rack.input']
    input.rewind if input.respond_to?(:rewind)
    form_vars = input.read
    input.rewind if input.respond_to?(:rewind)

    req_params  = Rack::Utils.parse_query(Rack::Utils.escape(form_vars))
    param_names = req_params['name']

    return true unless param_names.is_a?(Array)

    %w[biosample bioproject submission experiment run analysis].each do |kind|
      return false if param_names.count {|n| n == %("#{kind}") } > 1
    end

    dra_types = %w[submission experiment run analysis]
    sent      = params.keys

    if dra_types.any? { sent.include?(it) }
      return false unless sent.include?('submission') && sent.include?('experiment') && sent.include?('run')
    end

    true
  end

  def save_uploaded_file (output_dir, category)
    save_dir = File.join(output_dir, category)
    FileUtils.mkdir_p(save_dir)

    upload = params[category]

    if upload.is_a?(String)
      save_path = File.join(save_dir, category)
      File.write(save_path, upload)
    else
      save_path = File.join(save_dir, upload.original_filename)
      FileUtils.cp(upload.tempfile.path, save_path)
    end

    save_path
  end

  def detect_file_format (category)
    upload = params[category]
    return nil if upload.is_a?(String)

    content_type = upload.content_type.to_s.strip

    case content_type
    when 'text/xml', 'application/xml'                                           then return 'xml'
    when 'application/json'                                                      then return 'json'
    when 'text/tab-separated-values', 'text/plain'                               then return 'tsv'
    when 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'     then return 'excel'
    end

    filename = upload.original_filename.to_s.strip.downcase

    return 'xml'  if filename.end_with?('.xml')
    return 'json' if filename.end_with?('.json')
    return 'tsv'  if filename.end_with?('.tsv', '.txt')
    return 'excel' if filename.end_with?('.xlsx', '.xlmx')

    nil
  end

  def write_status_file (path, payload)
    File.write(path, JSON.generate(payload))
  end
end
