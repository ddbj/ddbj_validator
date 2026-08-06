#!/usr/bin/env ruby
# テストが参照する tax_id とその祖先だけを抜き出した小さな taxonomy.sqlite3 を作る。
#
#   ruby test/fixtures/taxonomy/extract.rb <full-taxonomy.sqlite3> <output.sqlite3>
#
# 元は本番 Virtuoso から SSH トンネル越しに TTL を抜いていた (旧
# test/fixtures/virtuoso/extract_taxonomy.rb)。taxonomy がファイルになったので、
# data_updater/taxonomy/generate.rb が作ったものから切り出すだけで済む。
require 'set'
require 'sqlite3'

# テストコードと fixture から拾った tax_id
SEED_TAX_IDS = %w[
  1 2 561 562 1142 1148 1313 1314 1406378 1409 1416348 1445577 1515699
  1617264 5206 6231 7227 9606 10088 10090 10228 11320 1198036 12906
  103690 109903 1003037 1111708 1218073 1218099 1219033 1219034 1219044
  1219045 1219053 1219061 1223495 1223506 1223508 1223531 1223534
  1236543 1274375 1314752 2306576 282702 28384 32133 32644 410658
  447426 510903 539655 564289 655179 655401 662107 702656
].map(&:to_i).uniq.freeze

# 系統の判定に使う定数 (OrganismValidator の TAX_*)。祖先として辿り着けないと
# has_linage が答えられないので、seed と同じ扱いで含める
LINEAGE_ROOTS = %w[
  1 2 1117 10239 4751 2157 12884 33208 3193 12908 28384 9606 33090 2759 408169 2697049 527639
].map(&:to_i).freeze

source, output = ARGV

abort "usage: #{$0} <full-taxonomy.sqlite3> <output.sqlite3>" unless source && output

full = SQLite3::Database.new(source, readonly: true)

wanted = (SEED_TAX_IDS + LINEAGE_ROOTS).to_set

# 祖先も入れないと系統の判定ができない
(SEED_TAX_IDS + LINEAGE_ROOTS).each do |tax_id|
  id = tax_id

  while id && id != 1
    parent = full.get_first_value('SELECT parent_tax_id FROM taxa WHERE tax_id = ?', [id])

    break unless parent

    wanted << parent
    id = parent
  end
end

# seed に存在しない tax_id が混ざっていても黙って小さい fixture ができるだけなので、
# 気付けるように出す (テストが「その tax_id が無い」ことに依存してしまう)
missing = (SEED_TAX_IDS + LINEAGE_ROOTS).reject { full.get_first_value('SELECT 1 FROM taxa WHERE tax_id = ?', [it]) }

warn "seed のうち taxonomy に存在しない tax_id: #{missing.sort.inspect}" if missing.any?

File.delete(output) if File.exist?(output)

small = SQLite3::Database.new(output)

small.execute_batch(full.get_first_value("SELECT group_concat(sql, ';') FROM sqlite_master WHERE type = 'table'") + ';')

ids = wanted.to_a.sort

small.transaction do
  full.execute("SELECT tax_id, parent_tax_id, rank, scientific_name FROM taxa WHERE tax_id IN (#{ids.join(', ')})").each do |row|
    small.execute('INSERT INTO taxa (tax_id, parent_tax_id, rank, scientific_name) VALUES (?, ?, ?, ?)', row)
  end

  full.execute("SELECT tax_id, name, name_class, name_lower FROM names WHERE tax_id IN (#{ids.join(', ')})").each do |row|
    small.execute('INSERT INTO names (tax_id, name, name_class, name_lower) VALUES (?, ?, ?, ?)', row)
  end

  full.execute('SELECT key, value FROM meta').each do |row|
    small.execute('INSERT INTO meta (key, value) VALUES (?, ?)', row)
  end
end

small.execute_batch(<<~SQL)
  CREATE INDEX names_on_name       ON names (name);
  CREATE INDEX names_on_name_lower ON names (name_lower);
  CREATE INDEX names_on_tax_id     ON names (tax_id);
SQL

small.execute('VACUUM')

warn "#{small.get_first_value('SELECT COUNT(*) FROM taxa')} taxa / #{small.get_first_value('SELECT COUNT(*) FROM names')} names -> #{output} (#{(File.size(output) / 1024.0).round} KB)"

small.close
full.close
