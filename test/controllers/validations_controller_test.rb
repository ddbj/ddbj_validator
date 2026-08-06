require 'test_helper'
require 'minitest/mock'
require 'securerandom'

class ValidationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @data_dir = Dir.mktmpdir('validator_data_test')
    @original_path = Rails.configuration.validator['api_log']['path']
    Rails.configuration.validator['api_log']['path'] = @data_dir

    # 検証を同期実行に差し替える。detached thread のままだと teardown の rm_rf と競合して
    # 結果を観測できず、スレッドの例外がテスト出力に漏れる
    @original_runner = ValidationsController.background_runner
    ValidationsController.background_runner = ->(&block) { block.call }
  end

  teardown do
    ValidationsController.background_runner = @original_runner
    Rails.configuration.validator['api_log']['path'] = @original_path
    FileUtils.rm_rf(@data_dir)
  end

  test 'GET /api/validation/:uuid with unknown uuid returns 404 Validation not found' do
    get '/api/validation/00000000-0000-0000-0000-000000000000'
    assert_response :not_found
    assert_equal 'Validation not found', JSON.parse(response.body)['message']
  end

  test 'GET /api/validation/:uuid/status with unknown uuid returns 404 Validation not found' do
    get '/api/validation/00000000-0000-0000-0000-000000000000/status'
    assert_response :not_found
    assert_equal 'Validation not found', JSON.parse(response.body)['message']
  end

  test 'GET /api/validation/:uuid/:filetype with unknown uuid returns 404' do
    get '/api/validation/00000000-0000-0000-0000-000000000000/biosample'
    assert_response :not_found
    assert_equal 'Validation file not found', JSON.parse(response.body)['message']
  end

  test 'GET /api/validation/:uuid/:filetype/autocorrect with unknown uuid returns 404' do
    get '/api/validation/00000000-0000-0000-0000-000000000000/biosample/autocorrect'
    assert_response :not_found
    assert_match 'Auto-correct data not found', JSON.parse(response.body)['message']
  end

  test 'GET /api/validation/:uuid/:filetype rejects traversal in filetype' do
    get '/api/validation/00000000-0000-0000-0000-000000000000/..%2F'
    assert_response :not_found
  end

  test 'POST /api/validation accepts a biosample submission and returns the uuid' do
    fake_validator = Object.new
    def fake_validator.execute(params)
      File.write(params[:output], JSON.generate({status: 'success'}))
    end

    DDBJValidator::Validator.stub :new, fake_validator do
      post '/api/validation', params: {biosample: '<BioSampleSet/>'}
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_match(/\A[0-9a-f-]{36}\z/, body['uuid'])
    assert_equal 'accepted', body['status']
    assert body['start_time']

    save_dir = File.join(@data_dir, body['uuid'][0..1], body['uuid'])
    assert File.exist?(File.join(save_dir, 'biosample', 'biosample'))
    assert_equal 'finished', JSON.parse(File.read(File.join(save_dir, 'status.json')))['status']
  end

  test 'POST /api/validation marks the status as error when the validation could not run' do
    fake_validator = Object.new
    def fake_validator.execute(_params)
      raise DDBJValidator::EndpointUnavailable, 'Virtuoso is down'
    end

    DDBJValidator::Validator.stub :new, fake_validator do
      post '/api/validation', params: {biosample: '<BioSampleSet/>'}
    end

    assert_response :success

    uuid        = JSON.parse(response.body)['uuid']
    status_json = JSON.parse(File.read(File.join(@data_dir, uuid[0..1], uuid, 'status.json')))

    # running のまま残すとクライアントは終わらない検証をポーリングし続ける
    assert_equal 'error', status_json['status']
    assert_equal true, status_json['retryable']
    # 例外メッセージには SPARQL クエリ全文や絶対パスが入るので外には出さない
    refute status_json.key?('message')
  end

  test 'POST /api/validation marks a bug as not retryable' do
    fake_validator = Object.new
    def fake_validator.execute(_params)
      raise DDBJValidator::QueryFailed, 'malformed query'
    end

    DDBJValidator::Validator.stub :new, fake_validator do
      post '/api/validation', params: {biosample: '<BioSampleSet/>'}
    end

    uuid        = JSON.parse(response.body)['uuid']
    status_json = JSON.parse(File.read(File.join(@data_dir, uuid[0..1], uuid, 'status.json')))

    assert_equal 'error', status_json['status']
    assert_equal false, status_json['retryable']
  end

  test 'GET /api/validation/:uuid returns the merged status + result' do
    uuid = stage_validation(status: 'finished', result: {'status' => 'success', 'messages' => []})

    get "/api/validation/#{uuid}"

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 'finished', body['status']
    assert_equal({'status' => 'success', 'messages' => []}, body['result'])
  end

  test 'GET /api/validation/:uuid returns 400 while still running' do
    uuid = stage_validation(status: 'running')

    get "/api/validation/#{uuid}"

    assert_response :bad_request
    assert_equal 'Validation process has not finished yet', JSON.parse(response.body)['message']
  end

  test 'GET /api/validation/:uuid returns 500 when the validation could not run' do
    # 設備障害で中断した場合は result.json 自体が無い
    uuid = stage_validation(status: 'error')

    get "/api/validation/#{uuid}"

    assert_response :internal_server_error
  end

  test 'GET /api/validation/:uuid returns 503 when the validation can be retried' do
    uuid = stage_validation(status: 'error', retryable: true)

    get "/api/validation/#{uuid}"

    assert_response :service_unavailable
  end

  test 'GET /api/validation/:uuid/status returns the status JSON' do
    uuid = stage_validation(status: 'running')

    get "/api/validation/#{uuid}/status"

    assert_response :success
    assert_equal 'application/json', response.media_type
    assert_equal 'running', JSON.parse(response.body)['status']
  end

  test 'GET /api/validation/:uuid/:filetype returns the uploaded file' do
    uuid     = SecureRandom.uuid
    file_dir = File.join(@data_dir, uuid[0..1], uuid, 'biosample')
    FileUtils.mkdir_p(file_dir)
    File.write(File.join(file_dir, 'sample.xml'), '<BioSampleSet/>')

    get "/api/validation/#{uuid}/biosample"

    assert_response :success
    assert_equal 'application/xml', response.media_type
    assert_match '<BioSampleSet', response.body
  end

  test 'GET /api/validation/:uuid/:filetype/autocorrect returns the annotated file' do
    uuid     = stage_validation(status: 'finished', result: {'status' => 'success'})
    file_dir = File.join(@data_dir, uuid[0..1], uuid, 'biosample')
    FileUtils.mkdir_p(file_dir)
    File.write(File.join(file_dir, 'sample.xml'), '<BioSampleSet/>')

    fake_annotator = Object.new
    def fake_annotator.create_annotated_file(_org, _result, output, _filetype, _accept)
      File.write(output, '<BioSampleSet annotated="yes"/>')
      {status: 'succeed', file_path: output, file_type: 'xml'}
    end

    DDBJValidator::AutoAnnotator.stub :new, fake_annotator do
      get "/api/validation/#{uuid}/biosample/autocorrect"
    end

    assert_response :success
    assert_match 'annotated="yes"', response.body
  end

  private

  def stage_validation(status:, result: nil, retryable: nil)
    uuid     = SecureRandom.uuid
    save_dir = File.join(@data_dir, uuid[0..1], uuid)
    FileUtils.mkdir_p(save_dir)
    File.write(File.join(save_dir, 'status.json'),
               JSON.generate({uuid: uuid, status: status, retryable: retryable, start_time: Time.now}))
    File.write(File.join(save_dir, 'result.json'), JSON.generate(result)) if result
    uuid
  end
end
