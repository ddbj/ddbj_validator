FROM ruby:4.0.3

# bundle install 用に Gemfile/Gemfile.lock だけ build 時にコピーする。スクリプト本体
# (create_log_pg.rb) は実行時に compose の bind mount (/rails/log_analysis) で見える。
COPY ./Gemfile ./Gemfile.lock /tmp/log_analysis/
WORKDIR /tmp/log_analysis
RUN bundle install
