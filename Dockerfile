FROM ruby:2.5

WORKDIR /usr/src/ddbj_validator/src

COPY src/Gemfile src/Gemfile.lock ./
RUN bundle install
COPY src ./

EXPOSE 3000
CMD ["bundle", "exec", "unicorn", "-c", "/usr/src/ddbj_validator/src/conf/unicorn.rb", "-E", "development"]
