require 'test_helper'
require 'minitest/mock'

class SubmissionsControllerTest < ActionDispatch::IntegrationTest
  test 'GET /api/submission/ids/:filetype without API_KEY returns 401' do
    get '/api/submission/ids/biosample'
    assert_response :unauthorized
    assert_equal 'application/json', response.media_type
  end

  test 'GET /api/submission/ids/:filetype with wrong API_KEY returns 401' do
    get '/api/submission/ids/biosample', headers: {'API_KEY' => 'wrong'}
    assert_response :unauthorized
  end

  test 'GET /api/submission/:filetype/:id without API_KEY returns 401' do
    get '/api/submission/biosample/SSUB000000'
    assert_response :unauthorized
  end

  test 'GET /api/submission/:filetype/:id with wrong API_KEY returns 401' do
    get '/api/submission/biosample/SSUB000000', headers: {'API_KEY' => 'wrong'}
    assert_response :unauthorized
  end

  test 'GET /api/submission/ids/biosample with API_KEY returns the submission ids' do
    fake = Object.new
    def fake.public_submission_id_list = %w[SSUB000001 SSUB000002]

    BioSampleSubmitter.stub :new, fake do
      get '/api/submission/ids/biosample', headers: {'HTTP_API_KEY' => 'curator'}
    end

    assert_response :success
    assert_equal %w[SSUB000001 SSUB000002], JSON.parse(response.body)
  end

  test 'GET /api/submission/ids/bioproject with API_KEY returns the submission ids' do
    fake = Object.new
    def fake.public_submission_id_list = %w[PSUB000001]

    BioProjectSubmitter.stub :new, fake do
      get '/api/submission/ids/bioproject', headers: {'HTTP_API_KEY' => 'curator'}
    end

    assert_response :success
    assert_equal %w[PSUB000001], JSON.parse(response.body)
  end

  test 'GET /api/submission/ids/:filetype with unknown filetype returns 400' do
    get '/api/submission/ids/unknown', headers: {'HTTP_API_KEY' => 'curator'}
    assert_response :bad_request
    assert_equal 'Invalid filetype', JSON.parse(response.body)['message']
  end

  # 過去に submission_id_list の rescue 節が代入式 (`ret[:status] = 'error'`)
  # で終わっていて、本来 ret hash を返すべきところを String 'error' を返していた。
  # その結果 controller 側の `ret[:status]` が TypeError を投げ、本来の
  # internal_server_error 応答に届かないまま落ちていた。
  test 'GET /api/submission/ids/:filetype returns 500 when submitter raises' do
    fake = Object.new
    def fake.public_submission_id_list = raise(StandardError, 'boom')

    BioSampleSubmitter.stub :new, fake do
      get '/api/submission/ids/biosample', headers: {'HTTP_API_KEY' => 'curator'}
    end

    assert_response :internal_server_error
  end

  test 'GET /api/submission/:filetype/:id with API_KEY returns the submission XML' do
    fake = Object.new
    def fake.output_xml_file(_submission_id, output)
      File.write(output, '<BioSampleSet/>')
    end

    BioSampleSubmitter.stub :new, fake do
      get '/api/submission/biosample/SSUB000001', headers: {'HTTP_API_KEY' => 'curator'}
    end

    assert_response :success
    assert_equal 'application/xml', response.media_type
    assert_match '<BioSampleSet', response.body
  end

  test 'GET /api/submission/:filetype/:id with unknown filetype returns 400' do
    get '/api/submission/unknown/SSUB000001', headers: {'HTTP_API_KEY' => 'curator'}
    assert_response :bad_request
    assert_equal 'Invalid filetype or submission_id', JSON.parse(response.body)['message']
  end

  test 'GET /api/submission/:filetype/:id returns 400 when submitter does not write the file' do
    fake = Object.new
    def fake.output_xml_file(_submission_id, _output) = nil

    BioSampleSubmitter.stub :new, fake do
      get '/api/submission/biosample/SSUB999999', headers: {'HTTP_API_KEY' => 'curator'}
    end

    assert_response :bad_request
    assert_equal 'Invalid filetype or submission_id', JSON.parse(response.body)['message']
  end

  test 'GET /api/submission/:filetype/:id returns 500 when submitter raises' do
    fake = Object.new
    def fake.output_xml_file(_submission_id, _output) = raise(StandardError, 'boom')

    BioSampleSubmitter.stub :new, fake do
      get '/api/submission/biosample/SSUB000001', headers: {'HTTP_API_KEY' => 'curator'}
    end

    assert_response :internal_server_error
  end
end
