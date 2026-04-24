require 'securerandom'

class ValidationsController < ApplicationController
  def create
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

      validation_params[category.to_sym]                  = save_uploaded_file(save_dir, category)
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

  def show
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

  def status
    status_file_path = File.join(data_dir, params[:uuid][0..1], params[:uuid], 'status.json')

    if File.exist?(status_file_path)
      send_file status_file_path, type: 'application/json', disposition: 'inline'
    else
      render_error('Invalid uuid', status: :bad_request)
    end
  end

  def file
    save_dir  = File.join(data_dir, params[:uuid][0..1], params[:uuid])
    file_list = Dir.glob(File.join(save_dir, params[:filetype], '*'))

    if params[:filetype] == 'jvar'
      send_jvar_file(file_list)
    elsif file_list.size == 1
      send_file file_list.first, filename: File.basename(file_list.first), type: 'application/xml'
    else
      render_error('Invalid uuid or filetype', status: :bad_request)
    end
  end

  def autocorrect
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
      send_file result[:file_path], filename: File.basename(result[:file_path]), type: autocorrect_mime(result[:file_type])
    end
  end

  private

  # jvar の結果は元ファイルが Excel だが変換された JSON を返すケースもあるので、
  # Accept ヘッダで xlsx / json を切り替える。
  def send_jvar_file (file_list)
    if accept_header.to_s.include?('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
      file = file_list.find {|f| f.end_with?('.xlsx') }
      type = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    else
      file = file_list.find {|f| f.end_with?('.json') }
      type = 'application/json'
    end

    if file
      send_file file, filename: File.basename(file), type: type
    else
      render_error('Invalid uuid or filetype', status: :bad_request)
    end
  end

  def autocorrect_mime (file_type)
    case file_type
    when 'json' then 'application/json'
    when 'tsv'  then 'text/tab-separated-values'
    else             'application/xml'
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

    case upload.content_type.to_s.strip
    when 'text/xml', 'application/xml'                                       then return 'xml'
    when 'application/json'                                                  then return 'json'
    when 'text/tab-separated-values', 'text/plain'                           then return 'tsv'
    when 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' then return 'excel'
    end

    filename = upload.original_filename.to_s.strip.downcase

    return 'xml'   if filename.end_with?('.xml')
    return 'json'  if filename.end_with?('.json')
    return 'tsv'   if filename.end_with?('.tsv', '.txt')
    return 'excel' if filename.end_with?('.xlsx', '.xlmx')

    nil
  end

  def write_status_file (path, payload)
    File.write(path, JSON.generate(payload))
  end
end
