FROM ruby:4.0.3

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT=development:test

WORKDIR /usr/src/ddbj_validator/

COPY ./Gemfile ./Gemfile.lock ./
RUN bundle install

COPY ./ ./

RUN SECRET_KEY_BASE=dummy bundle exec bootsnap precompile --gemfile app/ lib/ 2>/dev/null || true

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "/usr/src/ddbj_validator/config/puma.rb"]
