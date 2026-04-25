# syntax=docker/dockerfile:1
# check=error=true

# 本番向け Dockerfile。compose.yaml が host のソースを WORKDIR に bind mount するので、
# 最終 image にコードを焼き付けない (ビルド時のキャッシュ用に COPY はしている)。
# Rails 8 の scaffold Dockerfile に倣い multi-stage / slim base / jemalloc を採用。

ARG RUBY_VERSION=4.0.3
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# Install base packages (libpq for pg gem, libjemalloc2 for memory allocator)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libpq-dev libxslt1.1 libyaml-0-2 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libxslt-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

# Final stage for app image
FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
