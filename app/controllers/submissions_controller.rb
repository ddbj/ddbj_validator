require 'securerandom'

class SubmissionsController < ApplicationController
  before_action :authenticate_curator

  def ids
    ret = Submitter.new.submission_id_list(params[:filetype])

    case ret[:status]
    when 'success' then render json: ret[:data]
    when 'fail'    then render_error('Invalid filetype', status: :bad_request)
    else                head :internal_server_error
    end
  end

  def show
    uuid     = SecureRandom.uuid
    save_dir = File.join(data_dir, 'submission_xml', uuid[0..1], uuid)

    FileUtils.mkdir_p(save_dir)

    ret = Submitter.new.submission_xml(params[:filetype], params[:submission_id], save_dir)

    case ret[:status]
    when 'success' then send_file ret[:file_path], filename: File.basename(ret[:file_path]), type: 'application/xml'
    when 'fail'    then render_error('Invalid filetype or submission_id', status: :bad_request)
    else                head :internal_server_error
    end
  end

  private

  # request.headers['API_KEY'] は underscore を含むキーを HTTP_ プレフィックス変換
  # しないため env を直接参照する。旧 Sinatra 版の headers["HTTP_API_KEY"] と互換。
  def authenticate_curator
    return if request.env['HTTP_API_KEY'] == 'curator'

    send_file Rails.public_path.join('api/error_unauthorized.json'),
              type: 'application/json', disposition: 'inline', status: :unauthorized
  end
end
