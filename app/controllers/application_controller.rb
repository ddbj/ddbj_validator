class ApplicationController < ActionController::API
  # 想定外の例外は Rails.error.report (= Sentry に転送) して 500 を返す。
  # 個別 model の rescue でハンドルすべきは「想定済み」のフロー (例: 不正な
  # filetype を fail として返す等) のみ。
  rescue_from StandardError do |ex|
    Rails.error.report(ex)
    render_error 'Internal Server Error. An error occurred during processing.', status: :internal_server_error
  end

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
