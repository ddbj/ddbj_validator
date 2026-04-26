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

  test 'GET /api/attribute_template_file with TSV Accept header returns the .tsv template' do
    get '/api/attribute_template_file', params: {package: 'Plant', version: '1.4.0'},
                                        headers: {'Accept' => 'text/tab-separated-values'}
    assert_response :success
    assert_equal 'text/tab-separated-values', response.media_type
    assert_equal 'attachment; filename="template.tsv"; filename*=UTF-8\'\'template.tsv',
                 response.headers['Content-Disposition']
  end

  test 'GET /api/attribute_template_file defaults to the BioProject + BioSample Excel template' do
    get '/api/attribute_template_file', params: {package: 'Plant', version: '1.4.0'}
    assert_response :success
    assert_equal 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', response.media_type
    assert_equal File.size('public/template/1.4.0/bpbs/excel/Plant.xlsx'),
                 response.body.bytesize
  end

  test 'GET /api/attribute_template_file with only_biosample_sheet returns the BioSample-only Excel template' do
    get '/api/attribute_template_file', params: {package: 'Plant', version: '1.4.0', only_biosample_sheet: true}
    assert_response :success
    assert_equal 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', response.media_type
    assert_equal File.size('public/template/1.4.0/bs/excel/Plant.xlsx'),
                 response.body.bytesize
  end

  test 'GET /api/attribute_template_file with version below 1.4 returns 400' do
    get '/api/attribute_template_file', params: {package: 'Plant', version: '1.3.0'}
    assert_response :bad_request
    assert_match 'Invalid package version', JSON.parse(response.body)['message']
  end

  test 'GET /api/attribute_template_file with unknown package returns 400' do
    get '/api/attribute_template_file', params: {package: 'NonExistentPackage', version: '1.4.0'}
    assert_response :bad_request
    assert_equal 'Invalid package_id', JSON.parse(response.body)['message']
  end

  test 'GET /api/package_info without package param returns 400' do
    get '/api/package_info'
    assert_response :bad_request
    assert_equal "'package' parameter is required", JSON.parse(response.body)['message']
  end
end
