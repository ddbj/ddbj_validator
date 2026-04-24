class ApplicationController < ActionController::API
  before_action :set_cors_headers

  private

  def set_cors_headers
    response.headers['Access-Control-Allow-Origin'] = '*'
  end

  def validator_setting
    Rails.configuration.validator
  end

  def biosample_package_version
    BioSampleValidator::DEFAULT_PACKAGE_VERSION
  end

  def data_dir
    validator_setting['api_log']['path']
  end

  # Accept ヘッダをリストで返す (旧実装互換)。
  def accept_header
    request.env.select {|k, _| k.start_with?('HTTP_ACCEPT') }.presence || []
  end

  def render_error (message, status:)
    render json: {status: 'error', message: message}, status: status
  end

  def require_curator!
    return if request.headers['API_KEY'] == 'curator'

    send_file Rails.public_path.join('error_unauthorized.json'),
              type: 'application/json', disposition: 'inline', status: :unauthorized
  end

  def http_get_response (uri, options = {})
    url = URI.parse(uri)
    req = Net::HTTP::Get.new(url)
    options.each {|k, v| req[k] = v }
    Net::HTTP.start(url.host, url.port, use_ssl: uri.start_with?('https')) {|http|
      http.request(req)
    }
  end

  def http_post_response (uri, data, options = {})
    url = URI.parse(uri)
    req = Net::HTTP::Post.new(url)
    req.set_form(data, 'multipart/form-data')
    options.each {|k, v| req[k] = v }
    Net::HTTP.start(url.host, url.port, use_ssl: uri.start_with?('https')) {|http|
      http.request(req)
    }
  end
end
