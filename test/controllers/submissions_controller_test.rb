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
end
