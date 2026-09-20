# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Everything runs in Docker

There is no host-side Ruby toolchain to rely on. Never suggest running `bundle`,
`bin/rails`, `bin/rspec` or `psql` directly on the host — every command goes
through Compose.

```bash
docker compose up                                    # db + web on :3000
docker compose run --rm web bin/rails db:prepare
docker compose run --rm web bin/rails generate model Meal name:string
docker compose run --rm web bin/rspec                # whole suite
docker compose run --rm web bin/rspec spec/models/meal_spec.rb:12   # one example
docker compose run --rm web bin/rubocop
docker compose run --rm web bin/ci                   # full CI sequence locally
docker compose exec web bin/rails console            # against a running server
```

Adding a gem needs no rebuild: `bin/docker-entrypoint-dev` runs
`bundle check || bundle install` on every container start. A rebuild
(`docker compose build web`) is only needed when the `Dockerfile` itself changes.

## Container architecture

One multi-stage `Dockerfile` serves both environments so they cannot drift:

- `base` — Ruby 3.4.10 slim plus the shared system libraries.
- `development` — adds the build toolchain and the development/test gem groups.
  Used by `compose.yaml` via `target: development`.
- `build` → `production` — the default target. `docker build .` produces the
  deployable image.

The `development` stage runs as **UID 1000** deliberately. The source tree is
bind-mounted, so files created by generators inside the container must be owned
by the host user rather than root.

`compose.prod.yaml` runs the production target against a remote database, to
smoke-test the exact image before deploying it.

## Two environment traps specific to this setup

**`config/database.yml` uses discrete `POSTGRES_*` variables for development and
test, never `DATABASE_URL`.** Rails merges `DATABASE_URL` into whichever
environment is loaded, so setting it would make the test suite run against the
development database. `DATABASE_URL` is reserved for production. The host
defaults to `db`, the Compose service name — anything running outside Compose
(such as the GitHub Actions `test` job) must override `POSTGRES_HOST`.

**`spec/rails_helper.rb` assigns `ENV['RAILS_ENV'] = 'test'` rather than the
generated `||=`.** The development image pins `RAILS_ENV=development`, which
would otherwise leak into the suite. If specs ever start failing with
`uninitialized constant Shoulda`, this is why: the `:test` gem group is not
being loaded.

## Testing

RSpec, not Minitest. The app was generated with `--skip-test`, so there is no
`test/` directory and `rails/test_unit/railtie` stays commented out in
`config/application.rb`.

`config.generators` is wired so `bin/rails generate model` produces a spec and a
FactoryBot factory. `spec/rails_helper.rb` includes `FactoryBot::Syntax::Methods`
(call `create(:meal)`, not `FactoryBot.create(:meal)`) and configures
shoulda-matchers. Files under `spec/support/` are auto-required.

`config.infer_spec_type_from_file_location!` is left off, per RSpec's own
guidance — declare `type: :model`, `type: :request` and so on explicitly.

## CI

`config/ci.rb` defines the sequence (`bin/ci` runs it): setup, RuboCop, RSpec,
bundler-audit, importmap audit, Brakeman. `.github/workflows/ci.yml` mirrors it
as separate jobs, with the `test` job using a Postgres service container.

RuboCop is `rubocop-rails-omakase`. Keep it clean — CI gates on it.

## Deploying

Target: **Render** (Docker web service, free tier, 512 MB RAM, sleeps after 15
minutes idle) plus **Neon** serverless Postgres, a single database reached
entirely through `DATABASE_URL`. The blueprint is `render.yaml` at the repo
root.

Required env vars (set in Render's dashboard when prompted by the blueprint,
never committed): `DATABASE_URL`, `RAILS_MASTER_KEY`, `GOOGLE_CLIENT_ID`,
`GOOGLE_CLIENT_SECRET`, `ALLOWED_EMAILS`.

The solid_* stack (`solid_cache`, `solid_queue`, `solid_cable`) was
deliberately removed: with one database, two users, no background jobs and no
websockets anywhere in the app, those gems were pure weight on a 512 MB
instance. Production uses `:memory_store` for caching, `:async` for both
Active Job and Action Cable.

**Start command.** The Dockerfile's default `CMD` boots through Thruster on
port 80 and is left unchanged (`compose.prod.yaml` depends on it), but Render
injects its own `$PORT` and Thruster would collide with Puma over it.
`render.yaml` overrides the start command for the deployed service to bind
Puma directly: `./bin/rails server -b 0.0.0.0 -p $PORT`. `bin/docker-entrypoint`
detects any `./bin/rails server` invocation regardless of trailing flags and
runs `db:prepare` first — see its comment for why the check is shaped that
way (it must not fire for `console` or a one-off task).

**TLS.** Render terminates TLS at its proxy, so `config/environments/production.rb`
sets both `config.assume_ssl = true` and `config.force_ssl = true`. Without
`assume_ssl`, Rails would see plain HTTP behind the proxy and `force_ssl`
would redirect in a loop.

**Connection pool.** `RAILS_MAX_THREADS` (default 3, see `config/puma.rb`)
drives `max_connections` in `config/database.yml`'s production block, so the
pool matches Puma's thread count — no starvation, no over-allocating against
Neon's connection limit for two users on a single Puma process.
