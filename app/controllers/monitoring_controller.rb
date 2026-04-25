require 'http'
require 'tempfile'

class MonitoringController < ApplicationController
  # 本番 deploy 時の生存確認。biosample の実 validation を 1 サイクル回す。
  # NG のときは HTTP 503 で返すことで curl --fail probe を失敗させる。
  def show
    submission_id = validator_setting.dig('monitoring', 'ssub_id') || 'SSUB009526'
    api_url       = "http://localhost:#{ENV.fetch('PORT', '3000')}/api/"

    xml_body = HTTP.headers('API_KEY' => 'curator').get("#{api_url}submission/biosample/#{submission_id}").body.to_s
    raise "Can't get submission xml file. Please check the validation service." unless xml_body.start_with?('<?xml')

    tmp = Tempfile.open('test_biosample') {|f|
      f.puts(xml_body)
      f
    }

    uuid = HTTP.post("#{api_url}validation", form: {
      biosample: HTTP::FormData::File.new(tmp.path, filename: "#{submission_id}.xml")
    }).parse(:json)['uuid']

    final_status = nil

    50.times do
      final_status = HTTP.get("#{api_url}validation/#{uuid}/status").parse(:json)['status']

      break if %w[finished error].include?(final_status)

      sleep(2)
    end

    raise 'Validation processing timed out.' unless %w[finished error].include?(final_status)

    final_status = HTTP.get("#{api_url}validation/#{uuid}").parse(:json)['status']

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
end
