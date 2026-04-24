require 'test_helper'

class HomeControllerTest < ActionDispatch::IntegrationTest
  test 'GET /api serves the html index' do
    get '/api'
    assert_response :success
    assert_match %r{text/html}, response.media_type
  end

  test 'GET /api/apispec/ serves the API spec html' do
    get '/api/apispec/'
    assert_response :success
    assert_match %r{text/html}, response.media_type
  end

  test 'GET /api/client/index serves the client html' do
    get '/api/client/index'
    assert_response :success
    assert_match %r{text/html}, response.media_type
  end

  test 'GET /api/error_unauthorized.json returns 401 with json body' do
    get '/api/error_unauthorized.json'
    assert_response :unauthorized
    assert_equal 'application/json', response.media_type
  end

  test 'GET /api/error_forbidden.json returns 403 with json body' do
    get '/api/error_forbidden.json'
    assert_response :forbidden
    assert_equal 'application/json', response.media_type
  end

  test 'GET /api/error_not_found.json returns 404 with json body' do
    get '/api/error_not_found.json'
    assert_response :not_found
    assert_equal 'application/json', response.media_type
  end
end
