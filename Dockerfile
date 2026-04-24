FROM ruby:4.0.3

WORKDIR /usr/src/ddbj_validator/

COPY ./Gemfile ./Gemfile.lock ./
# Skip dev/test groups in the production image so rake/minitest/webmock and
# friends don't ship to servers. The config is written to .bundle/config and
# persists for subsequent `bundle exec` invocations in this image.
RUN bundle config set --local without 'development test' && bundle install
COPY ./ ./

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "/usr/src/ddbj_validator/conf/puma.rb", "-e", "production"]
