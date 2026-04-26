class ApplicationController < ActionController::API
  private

  def validator_setting
    Rails.configuration.validator
  end

  def biosample_package_version
    Rails.configuration.validator['biosample']['package_version']
  end

  def data_dir
    validator_setting['api_log']['path']
  end

  def accept_header
    request.headers['Accept'].to_s
  end

  def render_error (message, status:)
    render json: {status: 'error', message: message}, status: status
  end
end
