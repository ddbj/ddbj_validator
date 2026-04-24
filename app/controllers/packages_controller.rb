class PackagesController < ApplicationController
  def list
    render_package_result(sparql_package.package_list(requested_version))
  end

  def list_with_groups
    render_package_result(sparql_package.package_and_group_list(requested_version))
  end

  def attributes
    return unless require_package_param

    render_package_result(sparql_package.attribute_list(requested_version, params[:package]))
  end

  def attribute_template
    return unless require_package_param

    ret = Package.new(nil).attribute_template_file(requested_version, params[:package], params[:only_biosample_sheet].present?, accept_header)

    case ret[:status]
    when 'success'
      if ret[:file_type] == 'tsv'
        send_file ret[:file_path], filename: 'template.tsv', type: 'text/tab-separated-values'
      else
        send_file ret[:file_path], filename: 'template.xlsx', type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      end
    when 'fail' then render_error(ret[:message], status: :bad_request)
    else             render_error(ret[:message], status: :internal_server_error)
    end
  end

  def info
    return unless require_package_param

    render_package_result(sparql_package.package_info(requested_version, params[:package]))
  end

  private

  def sparql_package
    Package.new(validator_setting['sparql_endpoint']['master_endpoint'])
  end

  def requested_version
    params[:version].presence || biosample_package_version
  end

  def require_package_param
    return true if params[:package].present?

    render_error("'package' parameter is required", status: :bad_request)
    false
  end

  def render_package_result (ret)
    case ret[:status]
    when 'success' then render json: ret[:data]
    when 'fail'    then render_error(ret[:message], status: :bad_request)
    else                render_error(ret[:message], status: :internal_server_error)
    end
  end
end
