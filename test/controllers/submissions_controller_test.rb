require 'test_helper'

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
end
