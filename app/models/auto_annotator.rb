# 元ファイルからAuto annotateしたファイルを生成して返す
class AutoAnnotator
  def initialize
    @setting = Rails.configuration.validator
  end

  # Executes auto annotation
  # Validationした元データファイルとValidationの結果からAnnotationした結果ファイルを生成して返す
  #
  # @param org_file 元ファイル(Validateしたファイル)
  # @param result_file Validator結果のJSON
  # @param annotated_file_path出力ファイルパス
  # @accept_header Accept ヘッダ値. ユーザ希望の出力形式 e.g. "text/html,text/tab-separated-values"
  # @return result  {status: "succeed", file: annotated_file_path} or {status: "error", message: message}
  def create_annotated_file(org_file, result_file, annotated_file_path, filetype, accept_header)
    info = {orginal_file: org_file.to_s, output_file: annotated_file_path}
    Rails.logger.info("execute auto_annotation: #{info}")
    begin
      accept_header_list = accept_header.to_s.split(',').map(&:strip)
      input_file_format = ''
      return_file_format = ''
      if filetype == 'biosample'
        file_info = FileParser.new().get_file_data(org_file) # 元ファイルの形式を調べる。これはかなり無駄
        unless file_info.nil?
          if file_info[:format] == 'xml'
            input_file_format = 'xml'
            return_file_format = 'xml'
            annotator = AutoAnnotatorXml.new
          elsif file_info[:format] == 'tsv'
            input_file_format = 'tsv'
            annotator = AutoAnnotatorTsv.new
            return_file_format = 'tsv' # 基本はTSVで返す
            return_file_format = 'json' if accept_header_list.include?('application/json')
          elsif file_info[:format] == 'json'
            input_file_format = 'json'
            annotator = AutoAnnotatorJson.new
            return_file_format = 'json' # 基本はJSONで返す
            return_file_format = 'tsv' if accept_header_list.include?('text/tab-separated-values')
          elsif file_info[:format] == 'unknown'
            raise "Can't parse bioproject original file type. #{org_file}"
          end
        else
          raise "Can't parse bioproject original file type. #{org_file}"
        end
      elsif filetype == 'bioproject'
        file_info = FileParser.new().get_file_data(org_file) # 元ファイルの形式を調べる。これはかなり無駄
        unless file_info.nil?
          if file_info[:format] == 'xml'
            input_file_format = 'xml'
            return_file_format = 'xml'
            annotator = AutoAnnotatorXml.new
          elsif file_info[:format] == 'tsv'
            input_file_format = 'tsv'
            annotator = AutoAnnotatorTsv.new
            return_file_format = 'tsv' # 基本はTSVで返す
            return_file_format = 'json' if accept_header_list.include?('application/json')
          elsif file_info[:format] == 'json'
            input_file_format = 'json'
            annotator = AutoAnnotatorJson.new
            return_file_format = 'json' # 基本はJSONで返す
            return_file_format = 'tsv' if accept_header_list.include?('text/tab-separated-values')
          elsif file_info[:format] == 'unknown'
            raise "Can't parse bioproject original file type. #{org_file}"
          end
        else
          raise "Can't parse bioproject original file type. #{org_file}"
        end
      end

      # 実行
      annotator.create_annotated_file(org_file, result_file, annotated_file_path, filetype)

      if File.exist?(annotated_file_path)
        # 変換の必要があればここで変換する？というか変換後のファイルパスを返す？
        if return_file_format != input_file_format # 元データと異なるファイル形式で返す必要がある
          output_file_path = file_convert(filetype, annotated_file_path, input_file_format, return_file_format)
        else
          output_file_path = annotated_file_path
        end
        {status: 'succeed', file_path: output_file_path, file_type: return_file_format}
      else
        {status: 'error', message: 'Failed to output annotated file.'}
      end
    rescue => ex
      return_message = ex.message.size < 250 ? ex.message : ex.message.split(/\.|\n/).first # 長過ぎる場合は最初の一行を返す
      {status: 'error', message: "Failed to output annotated file. #{return_message}"}
    end
  end

  # レスポンスのファイル形式に変換したファイルを出力する
  def file_convert(file_type, annotated_file_path, input_file_format, output_file_format)
    ret = nil
    if file_type == 'bioproject'
      if input_file_format == 'tsv' && output_file_format == 'json' # tsv => json
        if m = annotated_file_path.end_with?('.tsv')
          output_file = annotated_file_path.sub(/.tsv$/, '.json')
        else
          output_file = annotated_file_path + '.json'
        end
        unless output_file.nil?
          TsvFieldValidator.new().convert_tsv2json(annotated_file_path, output_file)
          ret = output_file
        end
      elsif input_file_format == 'json' && output_file_format == 'tsv' # json => tsv
        if m = annotated_file_path.end_with?('.json')
          output_file = annotated_file_path.sub(/.json$/, '.tsv')
        else
          output_file = annotated_file_path + '.tsv'
        end
        unless output_file.nil?
          TsvFieldValidator.new().convert_json2tsv(annotated_file_path, output_file)
          ret = output_file
        end
      end
    elsif file_type == 'biosample'
      if input_file_format == 'tsv' && output_file_format == 'json' # tsv => json
        if m = annotated_file_path.end_with?('.tsv')
          output_file = annotated_file_path.sub(/.tsv$/, '.json')
        else
          output_file = annotated_file_path + '.json'
        end
        unless output_file.nil?
          TsvColumnValidator.new().convert_tsv2biosample_json(annotated_file_path, output_file) # ヘッダーの*もつけたままのそのままの変換
          ret = output_file
        end
      elsif input_file_format == 'json' && output_file_format == 'tsv' # json => tsv
        if m = annotated_file_path.end_with?('.json')
          output_file = annotated_file_path.sub(/.json$/, '.tsv')
        else
          output_file = annotated_file_path + '.tsv'
        end
        unless output_file.nil?
          TsvColumnValidator.new().convert_json2tsv(annotated_file_path, output_file)
          ret = output_file
        end
      end
    end
    ret
  end
end
