FROM ruby:2.7.8

WORKDIR /usr/src/ddbj_validator/

COPY ./Gemfile ./Gemfile.lock ./
RUN gem install bundler -v 2.4.22
RUN bundle install
COPY ./ ./

EXPOSE 3000
CMD ["bundle", "exec", "unicorn", "-c", "/usr/src/ddbj_validator/conf/unicorn.rb", "-E", "development"]
