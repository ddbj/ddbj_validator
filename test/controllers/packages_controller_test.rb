require 'test_helper'

class PackagesControllerTest < ActionDispatch::IntegrationTest
  test 'GET /api/attribute_list without package param returns 400' do
    get '/api/attribute_list'
    assert_response :bad_request
    assert_equal "'package' parameter is required", JSON.parse(response.body)['message']
  end

  test 'GET /api/attribute_template_file without package param returns 400' do
    get '/api/attribute_template_file'
    assert_response :bad_request
    assert_equal "'package' parameter is required", JSON.parse(response.body)['message']
  end

  test 'GET /api/package_info without package param returns 400' do
    get '/api/package_info'
    assert_response :bad_request
    assert_equal "'package' parameter is required", JSON.parse(response.body)['message']
  end
end
