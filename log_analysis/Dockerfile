FROM ruby:2.5

RUN mkdir -p /usr/src/ddbj_validator/logs
RUN mkdir -p /usr/src/shared/log
RUN mkdir -p /usr/src/ddbj_validator/lib
COPY ./create_log_pg.rb /usr/src/log_analysis/
COPY ./Gemfile /usr/src/log_analysis/
COPY ./Gemfile.lock /usr/src/log_analysis/
WORKDIR /usr/src/log_analysis/

RUN bundle install
