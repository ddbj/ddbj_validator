FROM ruby:2.5

COPY src /usr/src/ddbj_validator/src
RUN mkdir -p /usr/src/ddbj_validator/logs
WORKDIR /usr/src/ddbj_validator/src

RUN bundle install

EXPOSE 3000
CMD ["bundle", "exec", "unicorn", "-c", "conf/unicorn.rb", "-E", "development"]
