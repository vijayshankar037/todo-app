FROM node:16-bullseye-slim AS assets

WORKDIR /app

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

COPY app/javascript ./app/javascript
COPY app/assets/stylesheets ./app/assets/stylesheets
RUN yarn build && yarn build:css

FROM ruby:3.1.2-slim-bullseye

RUN sed -i '/debian-security/d' /etc/apt/sources.list \
    && apt-get update -qq \
    && apt-get install --no-install-recommends -y build-essential libpq-dev libpq5 postgresql-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV RAILS_ENV=production \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_PATH=/usr/local/bundle \
    PATH="/opt/yarn-v1.22.19/bin:${PATH}" \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .
COPY --from=assets /app/app/assets/builds ./app/assets/builds
COPY --from=assets /app/node_modules ./node_modules
COPY --from=assets /usr/local/bin/node /usr/local/bin/node
COPY --from=assets /opt/yarn-v1.22.19 /opt/yarn-v1.22.19

RUN DATABASE_URL=postgresql://postgres:password@localhost/todo_app_build \
    SECRET_KEY_BASE=build-only-secret-key-base-for-assets-123456 \
    bundle exec rails assets:precompile \
    && useradd --create-home --shell /bin/bash app \
    && mkdir -p tmp/pids log storage \
    && chown -R app:app /app

USER app

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
