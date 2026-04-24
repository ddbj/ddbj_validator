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

  def accept_header
    request.env.select {|k, _| k.start_with?('HTTP_ACCEPT') }.presence || []
  end

  def render_error (message, status:)
    render json: {status: 'error', message: message}, status: status
  end
end
