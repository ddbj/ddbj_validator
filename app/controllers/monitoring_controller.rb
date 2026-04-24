require 'net/http'
require 'tempfile'

class MonitoringController < ApplicationController
  # 本番 deploy 時の生存確認。biosample の実 validation を 1 サイクル回す。
  # NG のときは HTTP 503 で返すことで curl --fail probe を失敗させる。
  def show
    submission_id = validator_setting.dig('monitoring', 'ssub_id') || 'SSUB009526'
    local_port    = ENV.fetch('DDBJ_VALIDATOR_APP_UNICORN_PORT', '3000')
    api_url       = "http://localhost:#{local_port}/api/"

    res = http_get(api_url + "submission/biosample/#{submission_id}", 'API_KEY' => 'curator')
    raise "Can't get submission xml file. Please check the validation service." unless res.body.start_with?('<?xml')

    tmp_xml_file = Tempfile.open('test_biosample') {|f|
      f.puts(res.body)
      f
    }

    post_data = [['biosample', tmp_xml_file.open, {filename: "#{submission_id}.xml"}]]
    res       = http_post(api_url + 'validation', post_data)
    uuid      = JSON.parse(res.body)['uuid']

    status = ''
    count  = 0

    until %w[finished error].include?(status)
      count += 1
      res    = http_get(api_url + "validation/#{uuid}/status")
      status = JSON.parse(res.body)['status']

      raise 'Validation processing timed out.' if count > 50

      sleep(2)
    end

    res          = http_get(api_url + "validation/#{uuid}")
    final_status = JSON.parse(res.body)['status']

    FileUtils.rm_rf(File.join(data_dir, uuid[0..1], uuid))

    if final_status == 'finished'
      render json: {status: 'OK', message: 'Validation processing has finished successfully.'}
    else
      render json: {status: 'NG', message: 'Validation processing finished with error. Please check the validation service.'},
             status: :service_unavailable
    end
  rescue => e
    render json: {status: 'NG', message: "Error has occurred during monitoring processing. Please check the validation service. #{e.message}"},
           status: :service_unavailable
  end

  private

  def http_get (uri, headers = {})
    url = URI.parse(uri)
    req = Net::HTTP::Get.new(url)
    headers.each {|k, v| req[k] = v }
    Net::HTTP.start(url.host, url.port, use_ssl: uri.start_with?('https')) {|http| http.request(req) }
  end

  def http_post (uri, data, headers = {})
    url = URI.parse(uri)
    req = Net::HTTP::Post.new(url)
    req.set_form(data, 'multipart/form-data')
    headers.each {|k, v| req[k] = v }
    Net::HTTP.start(url.host, url.port, use_ssl: uri.start_with?('https')) {|http| http.request(req) }
  end
end
