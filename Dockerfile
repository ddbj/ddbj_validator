FROM ruby:2.5

WORKDIR /usr/src/ddbj_validator/

COPY ./Gemfile ./Gemfile.lock ./
RUN bundle install
COPY ./ ./

EXPOSE 3000
CMD ["bundle", "exec", "unicorn", "-c", "/usr/src/ddbj_validator/conf/unicorn.rb", "-E", "development"]
