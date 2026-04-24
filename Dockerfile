FROM ruby:4.0.3

ENV RAILS_ENV=production \
    BUNDLE_WITHOUT=development:test

WORKDIR /usr/src/ddbj_validator/

COPY ./Gemfile ./Gemfile.lock ./
RUN bundle install

COPY ./ ./

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "/usr/src/ddbj_validator/config/puma.rb"]
