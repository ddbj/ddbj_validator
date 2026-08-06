module DDBJValidator
  # BioSample パッケージ定義を返す API。以前は版ごとの named graph に SPARQL を投げて
  # いたが、定義は gem に同梱されたので endpoint は要らなくなった (PackageDefinitions)。
  class Package
    def initialize (definitions = PackageDefinitions.new)
      @definitions = definitions
    end

    def package_list (version)
      ret = @definitions.package_list(version)
      if ret.any?
        {status: 'success', data: ret}
      else  # 結果が空の場合に存在するversionかチェック
        if @definitions.known_version?(version)
          {status: 'error', message: 'Processing finished with error. Please check the validation service.'}
        else
          {status: 'fail', message: 'Wrong parameter: invalid package version'}
        end
      end
    end

    # package_groupとpackageのリストをアプリ表示用に階層型に整形して返す
    def package_and_group_list (version)
      begin
        if version.split('.')[0..1].join('.').to_f < 1.4
          return {status: 'fail', message: 'Wrong parameter: This method is supported since version 1.4.'}
        end
      rescue
        return {status: 'fail', message: 'Wrong parameter: invalid package version.'}
      end

      # package listを取得
      package_list = @definitions.package_list(version)
      package_list.each do |row|
        row[:type] = 'package'
      end

      # package group listを取得
      package_group_list = @definitions.package_group_list(version)
      package_group_list.each do |row|
        row[:type] = 'package_group'
      end

      # mergeして階層型に整形
      package_list.concat(package_group_list)
      if package_list.any?
        package_tree = []
        package_list.each_with_index do |package_info, idx|
          package_tree = add_package_tree(package_info, package_list, package_tree)
        end
        {status: 'success', data: package_tree}
      else # 結果が空の場合に存在するversionかチェック
        if @definitions.known_version?(version)
          {status: 'error', message: 'Processing finished with error. Please check the validation service.'}
        else
          {status: 'fail', message: 'Wrong parameter: invalid package version.'}
        end
      end
    end

    # treeの中から再帰的にpackage_groupを探す。ヒットすればそのpackage_groupを返し、なければnilを返す
    def find_package_group(tree, group_info)
      return nil if group_info[:type] != 'package_group'
      hit_group = tree.find {|row| row[:package_group_name] == group_info[:package_group_name] }
      if hit_group.nil?
        tree.each do |package| # 下の階層から検索
          unless package[:package_list].nil? || package[:package_list] == []
            return find_package_group(package[:package_list], group_info) unless find_package_group(package[:package_list], group_info).nil?
          end
        end
        nil # 下の階層にもなければnil
      else
        hit_group
      end
    end

    def add_package_tree(package_info, package_list, tree)
      # 初回に出てきたpackage_groupにlistを追加
      if find_package_group(tree, package_info).nil? && package_info[:type] == 'package_group'
        package_info[:package_list] = []
      end

      # 親groupの記載がない(最上位)
      if package_info[:parent_package_group_uri].nil? || package_info[:parent_package_group_uri] == '' # find_package_group(tree, package_info).nil?
        if find_package_group(tree, package_info).nil?
          tree.push(package_info)
        end
        return tree
      end

      # 親を検索
      parent = package_list.find {|row| row[:type] == 'package_group' && row[:package_group_uri] == package_info[:parent_package_group_uri] }
      unless parent.nil?
        if find_package_group(tree, parent).nil? # まだ追加されていなければ
          tree = add_package_tree(parent, package_list, tree) # 親を追加
        end
        parent_group = find_package_group(tree, parent)
        parent_group[:package_list].push(package_info) if find_package_group(tree, package_info).nil?  # まだ追加されていなければ
      end
      tree
    end

    def attribute_list (version, package_id)
      attr_list = @definitions.attribute_list(version, package_id)
      if attr_list.any?
        group_list = @definitions.attribute_group_list(version, package_id)
        attr_list.each do |row|
          match = group_list.find {|group| group[:attribute_name] == row[:attribute_name] }
          unless match.nil?
            row[:require_type] = 'has_either_one_mandatory_attribute'
            row[:group_name] = match[:group_name]
          else
            row[:group_name] = ''
          end
        end
        {status: 'success', data: attr_list}
      else # 結果が空の場合に存在するversionかチェック
        if @definitions.known_version?(version)
          {status: 'fail', message: 'Wrong parameter: invalid package version or package id.'}
        else
          {status: 'fail', message: 'Wrong parameter: invalid package version.'}
        end
      end
    end

    def attribute_template_file (version, package_id, only_biosample_sheet, accept_header)
      unless version.split('.')[0..1].join('.').to_f >= 1.4 # 1.4以上でなければ
        return {status: 'fail', message: 'Invalid package version. Expected version is over 1.4'}
      end

      # accept header から希望ファイル形式を決める
      accept_header_list = accept_header.to_s.split(',').map(&:strip)
      return_file_format = accept_header_list.include?('text/tab-separated-values') ? 'tsv' : 'excel'
      template_file_dir = DDBJValidator.template_dir
      file_path = ''
      if return_file_format == 'tsv'
        file_path = "#{template_file_dir}/#{version}/bs/tsv/#{package_id}.tsv"
      else
        if only_biosample_sheet == true # BioSampleシートのみ
          file_path = "#{template_file_dir}/#{version}/bs/excel/#{package_id}.xlsx"
        else
          file_path = "#{template_file_dir}/#{version}/bpbs/excel/#{package_id}.xlsx"
        end
      end
      if File.exist?(file_path)
        {status: 'success', file_path: file_path, file_type: return_file_format}
      else
        DDBJValidator.logger.warn("Not exist package template file: #{file_path}")
        {status: 'fail', message: 'Invalid package_id'}
      end
    end

    def package_info (version, package_id)
      ret = @definitions.package_info(version, package_id)
      if ret.any?
        {status: 'success', data: ret.first}
      else  # 結果が空の場合に存在するversionかチェック
        if @definitions.known_version?(version)
          {status: 'fail', message: 'Wrong parameter: invalid package version or package id.'}
        else
          {status: 'fail', message: 'Wrong parameter: invalid package version.'}
        end
      end
    end

    private :find_package_group
    private :add_package_tree
  end
end
