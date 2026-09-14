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

## Deployment status

Not settled yet. The intended target is Supabase for Postgres plus a separate
free host for the container. Two things must be resolved first:

- `config/database.yml` declares separate `cache`, `queue` and `cable`
  databases for solid_cache/solid_queue/solid_cable. Supabase provides one.
- Supabase direct connections are IPv6-only. Connect through the Supavisor
  pooler on port **5432** (session mode); port 6543 is transaction mode and
  breaks Active Record's prepared statements.
