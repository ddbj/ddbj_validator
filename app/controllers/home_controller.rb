class HomeController < ApplicationController
  def index
    send_static 'api/index.html', 'text/html'
  end

  def apispec
    send_static 'api/apispec/index.html', 'text/html'
  end

  def client
    send_static 'api/client/index.html', 'text/html'
  end

  def error_unauthorized
    send_static 'error_unauthorized.json', 'application/json', status: :unauthorized
  end

  def error_forbidden
    send_static 'error_forbidden.json', 'application/json', status: :forbidden
  end

  def error_not_found
    send_static 'error_not_found.json', 'application/json', status: :not_found
  end

  private

  def send_static (relative_path, type, status: :ok)
    send_file Rails.public_path.join(relative_path), type: type, disposition: 'inline', status: status
  end
end
