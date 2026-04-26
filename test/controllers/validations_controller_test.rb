require 'test_helper'

class ValidationsControllerTest < ActionDispatch::IntegrationTest
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
end
