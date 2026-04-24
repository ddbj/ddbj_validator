require 'test_helper'

class ValidationsControllerTest < ActionDispatch::IntegrationTest
  test 'GET /api/validation/:uuid with unknown uuid returns 400 Invalid uuid' do
    get '/api/validation/00000000-0000-0000-0000-000000000000'
    assert_response :bad_request
    assert_equal 'Invalid uuid', JSON.parse(response.body)['message']
  end

  test 'GET /api/validation/:uuid/status with unknown uuid returns 400 Invalid uuid' do
    get '/api/validation/00000000-0000-0000-0000-000000000000/status'
    assert_response :bad_request
    assert_equal 'Invalid uuid', JSON.parse(response.body)['message']
  end

  test 'GET /api/validation/:uuid/:filetype with unknown uuid returns 400' do
    get '/api/validation/00000000-0000-0000-0000-000000000000/biosample'
    assert_response :bad_request
    assert_equal 'Invalid uuid or filetype', JSON.parse(response.body)['message']
  end

  test 'GET /api/validation/:uuid/:filetype/autocorrect with unknown uuid returns 400' do
    get '/api/validation/00000000-0000-0000-0000-000000000000/biosample/autocorrect'
    assert_response :bad_request
    assert_match 'Invalid uuid or filetype', JSON.parse(response.body)['message']
  end
end
