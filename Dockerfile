FROM ruby:2.4

COPY . /usr/src/ddbj_validator/
WORKDIR /usr/src/ddbj_validator/src

RUN bundle install --path vendor/bundle

EXPOSE 8090
CMD ["bundle", "exec", "unicorn", "-c", "../shared/config/unicorn.rb", "-E", "development", "-D"]
