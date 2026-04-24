FROM ruby:3.4.9

WORKDIR /usr/src/ddbj_validator/

COPY ./Gemfile ./Gemfile.lock ./
RUN bundle install
COPY ./ ./

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "/usr/src/ddbj_validator/conf/puma.rb", "-e", "development"]
