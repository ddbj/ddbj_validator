require 'securerandom'

class ValidationsController < ApplicationController
  # 検証は uuid を即返してバックグラウンドで走らせる。差し替え可能にしてあるのはテストが
  # 同期実行するため — detached thread のままだと teardown と競合して結果を観測できない。
  cattr_accessor :background_runner, default: ->(&block) { Thread.new(&block) }

  def create
    uuid       = SecureRandom.uuid
    save_dir   = File.join(data_dir, uuid[0..1], uuid)
    start_time = Time.now

    FileUtils.mkpath(save_dir)

    validation_params = {params: {'file_format' => {}}}

    # analysis は 2021-01-17 (d1566c0 "accept jvar excel input") に typo 化 ('analysisx') して
    # 入口を塞いだ状態が続いている。app/models/analysis_validator.rb 自体は残っているので
    # 再開するときはここに 'analysis' を足す。
    %w[all_db biosample bioproject submission experiment run jvar trad_anno trad_seq trad_agp metabobank_idf metabobank_sdrf].each do |category|
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

    background_runner.call do
      run_validation(validation_params, status_file_path, uuid: uuid, start_time: start_time)
    end

    render json: {uuid: uuid, status: 'accepted', start_time: start_time}
  end

  def show
    save_dir         = File.join(data_dir, params[:uuid][0..1], params[:uuid])
    status_file_path = File.join(save_dir, 'status.json')
    output_file_path = File.join(save_dir, 'result.json')

    status_json = JSON.parse(File.read(status_file_path))

    case status_json['status']
    when 'running'
      # まだ終わっていないだけ。結果がないことは異常ではない
      render_error('Validation process has not finished yet', status: :bad_request)
    when 'error'
      # 検証を実行できなかった。設備障害で中断した場合は result.json 自体が無い。
      # 例外の型は HTTP 越しには渡せないので、あとで聞き直せるかどうかだけを
      # ステータスコードで伝える (gem 側の EndpointUnavailable / それ以外に対応)
      head status_json['retryable'] ? :service_unavailable : :internal_server_error
    else
      result = JSON.parse(File.read(output_file_path))
      result = DDBJValidator::Validator.new.grouped_message(result) if params.key?('grouped_messages')

      render json: status_json.merge('result' => result)
    end
  rescue Errno::ENOENT
    render_error('Validation not found', status: :not_found)
  end

  def status
    status_file_path = File.join(data_dir, params[:uuid][0..1], params[:uuid], 'status.json')

    if File.exist?(status_file_path)
      send_file status_file_path, type: 'application/json', disposition: 'inline'
    else
      render_error('Validation not found', status: :not_found)
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
      render_error('Validation file not found', status: :not_found)
    end
  end

  def autocorrect
    save_dir      = File.join(data_dir, params[:uuid][0..1], params[:uuid])
    result_file   = File.join(save_dir, 'result.json')
    org_file_list = Dir.glob(File.join(save_dir, params[:filetype], '*'))

    unless File.exist?(result_file) && org_file_list.size == 1
      render_error('Auto-correct data not found for the given uuid / filetype', status: :not_found)
      return
    end

    org_file            = org_file_list.first
    annotated_file_dir  = File.join(save_dir, 'autoannotated', params[:filetype])
    annotated_file_name = "#{File.basename(org_file, '.*')}_annotated#{File.extname(org_file)}"
    annotated_file_path = File.join(annotated_file_dir, annotated_file_name)

    FileUtils.mkdir_p(annotated_file_dir)

    result = DDBJValidator::AutoAnnotator.new.create_annotated_file(org_file, result_file, annotated_file_path, params[:filetype], accept_header)

    if result.nil? || result[:status] != 'succeed'
      render json: {status: 'error', message: result && result[:message]}, status: :internal_server_error
    else
      send_file result[:file_path], filename: File.basename(result[:file_path]), type: autocorrect_mime(result[:file_type])
    end
  end

  private

  # 検証を実行し、status.json を終端状態 (finished / error) に更新する。
  #
  # ここで例外を握らずに抜けると status.json は running のまま残り、クライアントは
  # 終わらない検証をポーリングし続ける。設備障害 (DDBJValidator::EndpointUnavailable)
  # はまさにここへ届くので、検証できなかったことを status に書き切る。
  def run_validation (validation_params, status_file_path, uuid:, start_time:)
    DDBJValidator::Validator.new.execute(validation_params)

    result = JSON.parse(File.read(validation_params[:output]))
    status = result['status'] == 'error' ? 'error' : 'finished'

    write_status_file(status_file_path, {uuid: uuid, status: status, start_time: start_time, end_time: Time.now})
  rescue => ex
    DDBJValidator.error.report(ex)

    # ex.message は status エンドポイントがそのまま返すファイルに載る。SPARQL クエリ全文や
    # 絶対パス、エンドポイント URL が入っているので、外に出すのはリトライ可否だけにする。
    # 中身はログと Sentry にある
    retryable = ex.is_a?(DDBJValidator::EndpointUnavailable)

    write_status_file(status_file_path, {uuid: uuid, status: 'error', retryable: retryable, start_time: start_time, end_time: Time.now})
  end

  # jvar の結果は元ファイルが Excel だが変換された JSON を返すケースもあるので、
  # Accept ヘッダで xlsx / json を切り替える。
  def send_jvar_file (file_list)
    if accept_header.include?('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
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

  # status.json は web リクエストと validator スレッドが同時に読み書きするため、
  # 部分書き込みを掴ませないよう temp + rename でアトミックに置き換える。
  def write_status_file (path, payload)
    tmp = "#{path}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp"
    File.write(tmp, JSON.generate(payload))
    File.rename(tmp, path)
  end
end
