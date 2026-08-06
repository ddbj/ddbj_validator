module DDBJValidator
  class FileParser
    def initialize
      @setting = DDBJValidator.config
    end
    #
    # ファイルからフォーマットを判定してパースしたデータを返す
    #
    # ==== Args
    # file_path: テキストデータ
    # ext
    # ==== Return
    # "json", "xml", "tsv", "csv"のいずれか
    #
    def get_file_data(file_path, filetype = nil)
      ext = File.extname(file_path)
      format = nil
      if filetype == 'json' || ext.downcase == 'json'
        begin
          ret = JSON.parse(File.read(file_path))
          return {format: 'json', data: ret}
        rescue JSON::ParserError => ex # 拡張子と中身があっていない
          # xml / tsv 分岐と同じく理由を持って帰る。ここだけ捨てていたので、
          # 「JSON として壊れている」が理由のない invalid:json になっていた。
          # ファイル自体が読めない場合 (Errno) はここで握らず素通りさせる。
          return {format: 'invalid:json', message: ex.message, data: nil}
        end
      elsif filetype == 'xml' || ext.downcase == 'xml'
        begin
          document = Nokogiri::XML(File.read(file_path))
          if document.errors.empty?
            return {format: 'xml', data: document}
          else
            return {format: 'invalid:xml', message: document.errors.join(', '), data: nil}
          end
        rescue Nokogiri::XML::SyntaxError => ex # 拡張子と中身があっていない
          return {format: 'invalid:xml', message: ex.message, data: nil}
        end
      elsif filetype == 'tsv' || ext.downcase == 'tsv'
        ret = parse_csv(file_path, "\t")
        if ret[:data].nil?
          return {format: 'invalid:tsv', message: ret[:message], data: nil}
        else
          return {format: 'tsv', data: ret[:data]}
        end
      elsif ext.downcase == 'xlsx' || ext.downcase == 'xlmx'
        return {format: 'excel', data: nil}  # 扱わないのでパースしない
      elsif ext.downcase == 'csv'
        return {format: 'csv', data: nil}  # 扱わないのでパースしない
      else # 拡張子が明示的でなければ中身で判定
        # 読めなかった時点で打ち切る。以前は File.read の失敗も下の
        # フォールバックに流れ込み、「存在しないファイル」が「知らない形式」
        # として報告されていた。
        content = File.read(file_path)

        begin
          document = Nokogiri::XML(content)
          if document.errors.empty?
            return {format: 'xml', data: document}
          else
            raise Nokogiri::XML::SyntaxError, document.errors.join(', ')
          end
        rescue Nokogiri::XML::SyntaxError
          begin
            ret = JSON.parse(content)
            return {format: 'json', data: ret}
          rescue JSON::ParserError
            begin
              ret = parse_csv(file_path, "\t")
              if ret[:data].nil?
                return {format: 'unknown', message: ret[:message], data: nil}
              else
                return {format: 'tsv', data: ret[:data]}
              end
            rescue => ex
              DDBJValidator.logger.warn('Fail to parse a file as JSON/XML/TSV.')
              DDBJValidator.logger.warn(ex)
              return {format: 'unknown', message: ex.message, data: nil}
            end
          end
        end
      end
      format
    end

    # CSV(TSV)をパースする。ExcelからExportされたTSVファイルも極力パースする
    def parse_csv(file_path, col_sep, row_sep = nil)
      tsv_data = nil
      message = nil

      begin
        tsv_data = CSV.read(file_path, encoding: 'UTF-8:UTF-8', col_sep: col_sep)
      rescue => ex1
        if ex1.message.downcase.include?('invalid byte sequence') || ex1.message.downcase.include?('unquoted fields do not allow') # encodeか改行文字関連のエラー
          # Excel 由来のファイルは BOM 付き UTF-16 なので BOM で判別する。
          bom = File.read(file_path, 2, mode: 'rb')
          encoding = (bom == "\xFF\xFE".b || bom == "\xFE\xFF".b) ? 'UTF-16:UTF-8' : 'CP932:UTF-8'
          begin
            tsv_data = CSV.read(file_path, encoding: encoding, col_sep: col_sep, row_sep: "\r\n")
          rescue => ex2
            DDBJValidator.logger.warn('Fail to parse a file as TSV file. Invalid encoding or newline char.')
            DDBJValidator.logger.warn(ex2)
          end
        else # 文字コードに関係ないエラー
          DDBJValidator.logger.warn('Fail to parse a file as TSV file.')
          DDBJValidator.logger.warn(ex1)
          message = ex1.message
        end
      end
      {data: tsv_data, message: message}
    end
  end
end
