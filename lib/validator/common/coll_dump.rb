# NCBI の coll_dump.txt (https://ftp.ncbi.nlm.nih.gov/pub/taxonomy/coll_dump.txt) を
# specimen_voucher / culture_collection / bio_material の institution 名リストにパースする。
module CollDump
  #
  # coll_dump.txt ファイルをパースして、specimen_voucher / culture_collection / bio_material の
  # institution リストを返す。指定されたファイルが無ければ NCBI FTP から取得する。
  #
  # ==== Args
  # dump_file: coll_dump.txt のファイルパス
  # ==== Return
  # {
  #   culture_collection: ["ATCC", "NBRC", "JMRC:SF", ...],
  #   specimen_voucher:   ["ASU", "NBSB", "NBSB:Bird", ...],
  #   bio_material:       ["ABRC", "CIAT", "CIAT:Bean", ...]
  # }
  # ダウンロードに失敗した/ファイルが空の場合は nil
  #
  def self.parse (dump_file)
    # 指定された coll_dump.txt がない場合はダウンロードする
    unless File.exist?(dump_file)
      begin
        ftp = Net::FTP.new("ftp.ncbi.nlm.nih.gov")
        ftp.login
        ftp.passive = true
        ftp.chdir("/pub/taxonomy/")
        ftp.getbinaryfile('coll_dump.txt', dump_file, 1024)
      rescue
      ensure
        ftp.close unless ftp.nil?
      end
    end
    return nil if !File.exist?(dump_file) || File.size(dump_file) == 0

    ret = {culture_collection: [], specimen_voucher: [], bio_material: []}
    File.open(dump_file) do |f|
      f.each_line do |line|
        row = line.split("\t")
        next unless row.size >= 2

        keys = []
        keys.push(:culture_collection) if row[1].strip.include?('c')
        keys.push(:specimen_voucher)   if row[1].strip.include?('s')
        keys.push(:bio_material)       if row[1].strip.include?('b')
        next if keys.empty?

        parts = row[0].strip.split(":")
        keys.each do |key|
          if parts.size == 1 # only institution name
            ret[key].push(parts.first)
          else # with collection name (e.g. "NBSB:Bird")
            ret[key].push(parts.join(":"))
            ret[key].push(parts.first) # 念のため institution name だけも追加
          end
        end
      end
    end
    ret.each_value(&:uniq!)
    ret
  end
end
