require 'test_helper'

class PackagesControllerTest < ActionDispatch::IntegrationTest
  test 'GET /api/package_list without version falls back to configured biosample version' do
    get '/api/package_list'
    assert_response :success
    assert_kind_of Array, JSON.parse(response.body)
  end

  test 'GET /api/package_and_group_list without version falls back to configured biosample version' do
    get '/api/package_and_group_list'
    assert_response :success
    assert_kind_of Array, JSON.parse(response.body)
  end

  test 'GET /api/attribute_list with package but no version falls back to configured biosample version' do
    get '/api/attribute_list', params: {package: 'MIGS.vi.soil'}
    assert_response :success
    assert_kind_of Array, JSON.parse(response.body)
  end

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
