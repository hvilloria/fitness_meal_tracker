# Macro Tracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a mobile-first macro and calorie tracker where a signed-in user keeps a catalog of foods with per-100 g values, sets a macro goal, logs what they eat into four daily meals, and sees the day's progress against that goal.

**Architecture:** Plain Rails MVC with fat models. Server-rendered ERB with Turbo for navigation and Turbo Streams for incremental logging; Stimulus only for the live arithmetic in the goal and entry forms. Two plain Ruby objects carry the calculations that belong to no single record. Every macro figure on an `Entry` is computed once at write time and frozen — never recomputed on read.

**Tech Stack:** Ruby 3.4.10, Rails 8.1.3, PostgreSQL 17, Propshaft, importmap-rails, Turbo, Stimulus, dartsass-rails, omniauth-google-oauth2, RSpec, FactoryBot, shoulda-matchers.

**Spec:** `docs/superpowers/specs/2026-09-14-macro-tracker-design.md`

## Global Constraints

- **Every command runs through Docker.** Never invoke `bundle`, `bin/rails` or `bin/rspec` on the host. Prefix with `docker compose run --rm web` or `docker compose exec web`. See `CLAUDE.md`.
- **Ruby 3.4.10, Rails 8.1.3.** Do not upgrade either.
- **All primary keys are UUIDs.** Every `create_table` takes `id: :uuid`, every reference takes `type: :uuid`.
- **Application time zone is `America/Argentina/Buenos_Aires`.** Storage stays UTC.
- **The day ends at `users.day_cutoff_hour`, default 4.** No query may derive a date with `Date.current` or `Time.current.to_date`. They all go through `DayLog.logical_date`.
- **`Entry` macros are frozen at write time.** Nothing recomputes them on read. Editing an entry calls `recalculate!` explicitly.
- **Macro arithmetic constants are 4 kcal/g protein, 4 kcal/g carbs, 9 kcal/g fat.** They live in `MacroSplit` and are referenced from there, never retyped.
- **Money-style precision:** all macro and gram columns are `decimal(8, 2)`. Round only for display.
- **RSpec spec types are explicit.** `config.infer_spec_type_from_file_location!` is off, so every describe block declares `type: :model`, `type: :request`, etc.
- **RuboCop must stay clean.** `rubocop-rails-omakase`. CI gates on it.
- **Everything written into files is in English** — code, comments, commit messages. UI copy is Spanish.
- **Mobile-first.** Design for a 375 px viewport first; widen with `min-width` media queries only.

---

### Task 1: UUID keys, time zone, and the Sass pipeline

Infrastructure only. No models yet, but every later migration depends on the UUID generator default and every later view depends on the stylesheet being compiled.

**Files:**
- Modify: `config/application.rb`
- Modify: `Gemfile`
- Modify: `compose.yaml`
- Modify: `.gitignore`
- Create: `app/assets/stylesheets/application.scss`
- Test: `spec/models/application_record_spec.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `config.generators` emitting `id: :uuid`; `Time.zone` set to `America/Argentina/Buenos_Aires`; a compiled `app/assets/builds/application.css`.

- [ ] **Step 1: Add the Sass gem**

Add to `Gemfile`, after the `propshaft` line:

```ruby
# Sass for the stylesheet, compiled by the css service in compose.yaml
gem "dartsass-rails"
```

- [ ] **Step 2: Install the gem and run its installer**

```bash
docker compose run --rm web bundle install
docker compose run --rm web bin/rails dartsass:install
```

This creates `app/assets/stylesheets/application.scss` and adds `app/assets/builds` to `.gitignore`. Verify both happened before continuing.

- [ ] **Step 3: Verify dart-sass runs inside the slim image**

```bash
docker compose run --rm web bin/rails dartsass:build
```

Expected: exits 0 and `app/assets/builds/application.css` exists. This is the risk the spec flags — if the binary does not run on `ruby:3.4.10-slim`, stop and report rather than working around it.

- [ ] **Step 4: Add the css watcher service**

In `compose.yaml`, after the `web` service:

```yaml
  css:
    build:
      context: .
      target: development
    command: bin/rails dartsass:watch
    environment:
      POSTGRES_HOST: db
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-postgres}
    volumes:
      - .:/rails
      - bundle:/usr/local/bundle
    depends_on:
      db:
        condition: service_healthy
```

- [ ] **Step 5: Configure the time zone and UUID generators**

In `config/application.rb`, inside the `Application` class, replace the existing generators block with:

```ruby
    config.time_zone = "America/Argentina/Buenos_Aires"

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Generate RSpec specs and FactoryBot factories instead of Minitest files.
    config.generators do |g|
      g.test_framework :rspec
      g.factory_bot dir: "spec/factories"
      g.orm :active_record, primary_key_type: :uuid
    end
```

- [ ] **Step 6: Write the failing test**

Create `spec/models/application_record_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe ApplicationRecord, type: :model do
  it "runs the application in the Buenos Aires time zone" do
    expect(Time.zone.name).to eq("America/Argentina/Buenos_Aires")
  end

  it "stores timestamps in UTC" do
    # ActiveRecord.default_timezone, not ActiveRecord::Base.default_timezone —
    # the latter was deprecated in Rails 7.0 and removed in 7.1.
    expect(ActiveRecord.default_timezone).to eq(:utc)
  end
end
```

- [ ] **Step 7: Run the test**

```bash
docker compose run --rm web bin/rspec spec/models/application_record_spec.rb
```

Expected: PASS. If the time zone assertion fails, `config.time_zone` was not applied.

- [ ] **Step 8: Verify the watcher and lint**

```bash
docker compose up -d css
docker compose logs css | tail -5
docker compose run --rm web bin/rubocop
```

Expected: the css service reports it is watching; RuboCop reports no offenses.

- [ ] **Step 9: Commit**

```bash
git add Gemfile Gemfile.lock compose.yaml config/application.rb .gitignore app/assets/stylesheets spec/models/application_record_spec.rb
git commit -m "Configure UUID keys, Buenos Aires time zone and the Sass pipeline"
```

---

### Task 2: Google authentication with an email allowlist

**Files:**
- Modify: `Gemfile`
- Create: `db/migrate/<timestamp>_create_users.rb`
- Create: `app/models/user.rb`
- Create: `app/controllers/sessions_controller.rb`
- Modify: `app/controllers/application_controller.rb`
- Create: `config/initializers/omniauth.rb`
- Modify: `config/routes.rb`
- Modify: `.env.example`, `.env`
- Create: `spec/factories/users.rb`
- Create: `spec/support/omniauth.rb`
- Test: `spec/models/user_spec.rb`, `spec/requests/sessions_spec.rb`

**Interfaces:**
- Consumes: UUID generators from Task 1.
- Produces: `User` with `id`, `email`, `name`, `avatar_url`, `provider`, `uid`, `day_cutoff_hour`; `User.from_omniauth(auth)` returning a `User` or `nil` when the email is not allowed; `User.allowed?(email)` returning a boolean; `ApplicationController#current_user` returning `User` or `nil`; `ApplicationController#require_authentication` as a `before_action`.

- [ ] **Step 1: Add the gems**

Add to `Gemfile`, after the `jbuilder` line:

```ruby
# Google sign-in. No passwords, so no Devise.
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"
```

Then:

```bash
docker compose run --rm web bundle install
```

- [ ] **Step 2: Write the failing model test**

Create `spec/models/user_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe User, type: :model do
  def auth_hash(email:, uid: "123", name: "Hosward", image: "http://example.com/a.jpg")
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { email: email, name: name, image: image }
    )
  end

  describe ".allowed?" do
    it "accepts an email listed in ALLOWED_EMAILS" do
      allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com,b@example.com")
      expect(User.allowed?("b@example.com")).to be(true)
    end

    it "rejects an email that is not listed" do
      allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
      expect(User.allowed?("intruder@example.com")).to be(false)
    end

    it "ignores surrounding whitespace and case" do
      allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return(" A@Example.com , b@example.com ")
      expect(User.allowed?("a@example.com")).to be(true)
    end

    it "rejects everything when ALLOWED_EMAILS is unset" do
      allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return(nil)
      expect(User.allowed?("a@example.com")).to be(false)
    end
  end

  describe ".from_omniauth" do
    before do
      allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
    end

    it "creates a user for an allowed email" do
      expect { User.from_omniauth(auth_hash(email: "a@example.com")) }
        .to change(User, :count).by(1)
    end

    it "returns nil and creates nothing for a disallowed email" do
      expect { expect(User.from_omniauth(auth_hash(email: "no@example.com"))).to be_nil }
        .not_to change(User, :count)
    end

    it "reuses the existing user and refreshes the profile" do
      User.from_omniauth(auth_hash(email: "a@example.com", name: "Old"))

      expect { User.from_omniauth(auth_hash(email: "a@example.com", name: "New")) }
        .not_to change(User, :count)
      expect(User.last.name).to eq("New")
    end

    it "defaults the day cutoff to 4" do
      user = User.from_omniauth(auth_hash(email: "a@example.com"))
      expect(user.day_cutoff_hour).to eq(4)
    end
  end
end
```

- [ ] **Step 3: Run it to confirm it fails**

```bash
docker compose run --rm web bin/rspec spec/models/user_spec.rb
```

Expected: FAIL with `uninitialized constant User`.

- [ ] **Step 4: Create the migration**

```bash
docker compose run --rm web bin/rails generate migration CreateUsers
```

Fill it in:

```ruby
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: :uuid do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :avatar_url
      t.string :provider, null: false
      t.string :uid, null: false
      t.integer :day_cutoff_hour, null: false, default: 4

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, [ :provider, :uid ], unique: true
  end
end
```

- [ ] **Step 5: Write the model**

Create `app/models/user.rb`:

```ruby
class User < ApplicationRecord
  validates :email, presence: true, uniqueness: true
  validates :name, presence: true
  validates :provider, :uid, presence: true
  validates :day_cutoff_hour, inclusion: { in: 0..23 }

  # Google sign-in is open to anyone with a Google account, so membership is
  # decided here rather than by the provider.
  def self.allowed?(email)
    return false if email.blank?

    allowlist = ENV["ALLOWED_EMAILS"].to_s.split(",").map { |entry| entry.strip.downcase }
    allowlist.include?(email.strip.downcase)
  end

  def self.from_omniauth(auth)
    email = auth.info.email
    return nil unless allowed?(email)

    user = find_or_initialize_by(provider: auth.provider, uid: auth.uid)
    user.email = email
    user.name = auth.info.name
    user.avatar_url = auth.info.image
    user.save!
    user
  end
end
```

- [ ] **Step 6: Migrate and run the test**

```bash
docker compose run --rm web bin/rails db:migrate
docker compose run --rm web bin/rspec spec/models/user_spec.rb
```

Expected: PASS, 8 examples.

- [ ] **Step 7: Add the factory**

Create `spec/factories/users.rb`:

```ruby
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    name { "Hosward" }
    provider { "google_oauth2" }
    sequence(:uid) { |n| "uid-#{n}" }
    day_cutoff_hour { 4 }
  end
end
```

- [ ] **Step 8: Configure OmniAuth**

Create `config/initializers/omniauth.rb`:

```ruby
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
    ENV["GOOGLE_CLIENT_ID"],
    ENV["GOOGLE_CLIENT_SECRET"],
    scope: "email,profile"
end

# omniauth-rails_csrf_protection requires the request phase to be a POST.
OmniAuth.config.allowed_request_methods = [ :post ]
```

Add to `.env.example` and `.env`:

```
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
ALLOWED_EMAILS=hosward.avc@gmail.com
```

- [ ] **Step 9: Add the OmniAuth test helper**

Create `spec/support/omniauth.rb`:

```ruby
OmniAuth.config.test_mode = true

module OmniAuthHelpers
  def sign_in_via_google(email:, name: "Hosward", uid: "uid-1")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { email: email, name: name, image: "http://example.com/a.jpg" }
    )
    get "/auth/google_oauth2/callback"
  end
end

RSpec.configure do |config|
  config.include OmniAuthHelpers, type: :request
  config.before { OmniAuth.config.mock_auth.clear }
end
```

- [ ] **Step 10: Write the failing request test**

Create `spec/requests/sessions_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Sessions", type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
  end

  it "signs in an allowed user and redirects to the day" do
    sign_in_via_google(email: "a@example.com")

    expect(response).to redirect_to(root_path)
    expect(session[:user_id]).to eq(User.last.id)
  end

  it "refuses a disallowed user" do
    sign_in_via_google(email: "intruder@example.com")

    expect(session[:user_id]).to be_nil
    expect(response).to redirect_to(sign_in_path)
    expect(flash[:alert]).to be_present
  end

  it "signs out" do
    sign_in_via_google(email: "a@example.com")
    delete sign_out_path

    expect(session[:user_id]).to be_nil
  end

  it "redirects an anonymous visitor to the sign-in page" do
    get root_path

    expect(response).to redirect_to(sign_in_path)
  end

  it "renders the sign-in page without a session" do
    get sign_in_path

    expect(response).to have_http_status(:ok)
  end
end
```

- [ ] **Step 11: Run it to confirm it fails**

```bash
docker compose run --rm web bin/rspec spec/requests/sessions_spec.rb
```

Expected: FAIL — the routes do not exist.

- [ ] **Step 12: Add routes**

In `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  get "sign_in", to: "sessions#new"
  post "/auth/:provider", to: "sessions#passthru", as: :auth_request
  get "/auth/:provider/callback", to: "sessions#create"
  get "/auth/failure", to: "sessions#failure"
  delete "sign_out", to: "sessions#destroy"

  get "up" => "rails/health#show", as: :rails_health_check

  root "days#show"
end
```

`sessions#passthru` is never reached — the OmniAuth middleware intercepts the POST. The route exists so `auth_request_path` can be used in the view.

- [ ] **Step 13: Write the controllers**

Create `app/controllers/sessions_controller.rb`:

```ruby
class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: %i[new create failure passthru]

  def new
    redirect_to root_path if current_user
  end

  def passthru
    head :not_found
  end

  def create
    user = User.from_omniauth(request.env["omniauth.auth"])

    if user
      session[:user_id] = user.id
      redirect_to root_path
    else
      redirect_to sign_in_path, alert: "Esa cuenta no tiene acceso a esta aplicación."
    end
  end

  def failure
    redirect_to sign_in_path, alert: "No se pudo completar el inicio de sesión."
  end

  def destroy
    session.delete(:user_id)
    redirect_to sign_in_path
  end
end
```

Replace `app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges,
  # import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :require_authentication

  private
    def current_user
      @current_user ||= User.find_by(id: session[:user_id])
    end
    helper_method :current_user

    def require_authentication
      redirect_to sign_in_path unless current_user
    end
end
```

- [ ] **Step 14: Add a minimal sign-in view**

Create `app/views/sessions/new.html.erb`:

```erb
<% content_for :title, "Entrar" %>

<main class="signin">
  <h1>Macros</h1>
  <%= button_to "Entrar con Google", auth_request_path(provider: "google_oauth2"), class: "button button--primary" %>
</main>
```

- [ ] **Step 15: Add a placeholder day screen**

`root_path` must resolve for the authentication tests to exercise the redirect. Task 6 replaces both files with the real thing.

Create `app/controllers/days_controller.rb`:

```ruby
class DaysController < ApplicationController
  def show
  end
end
```

Create `app/views/days/show.html.erb`:

```erb
<h1>Hoy</h1>
```

- [ ] **Step 16: Run the tests**

```bash
docker compose run --rm web bin/rspec spec/requests/sessions_spec.rb
```

Expected: PASS, 5 examples.

- [ ] **Step 17: Commit**

```bash
git add -A
git commit -m "Add Google sign-in restricted by an email allowlist"
```

---

### Task 3: Food catalog

**Files:**
- Create: `db/migrate/<timestamp>_create_foods.rb`
- Create: `app/models/food.rb`
- Modify: `app/models/user.rb`
- Create: `spec/factories/foods.rb`
- Test: `spec/models/food_spec.rb`

**Interfaces:**
- Consumes: `User` from Task 2.
- Produces: `Food` with `name`, `brand`, `state`, `kcal_per_100`, `protein_per_100`, `carbs_per_100`, `fat_per_100`, `fiber_per_100`, `sodium_per_100`, `sugar_per_100`, `archived_at`; `Food#display_name` returning `"name (brand)"` or `"name"`; `Food.active` scope; `Food::STATES`; `User#foods`.

- [ ] **Step 1: Write the failing test**

Create `spec/models/food_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Food, type: :model do
  subject(:food) { build(:food) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:state) }

  it "requires the four core macro fields" do
    food = build(:food, kcal_per_100: nil, protein_per_100: nil, carbs_per_100: nil, fat_per_100: nil)

    expect(food).not_to be_valid
    expect(food.errors.attribute_names)
      .to include(:kcal_per_100, :protein_per_100, :carbs_per_100, :fat_per_100)
  end

  it "rejects negative macro values" do
    expect(build(:food, protein_per_100: -1)).not_to be_valid
  end

  it "allows the optional micronutrients to be blank" do
    expect(build(:food, fiber_per_100: nil, sodium_per_100: nil, sugar_per_100: nil)).to be_valid
  end

  describe "#display_name" do
    it "includes the brand when there is one" do
      expect(build(:food, name: "Port Salut light", brand: "La Serenísima").display_name)
        .to eq("Port Salut light (La Serenísima)")
    end

    it "is just the name for a generic food" do
      expect(build(:food, name: "Pechuga de pollo", brand: nil).display_name)
        .to eq("Pechuga de pollo")
    end
  end

  describe ".active" do
    it "excludes archived foods" do
      live = create(:food)
      create(:food, archived_at: Time.current)

      expect(Food.active).to contain_exactly(live)
    end
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
docker compose run --rm web bin/rspec spec/models/food_spec.rb
```

Expected: FAIL with `uninitialized constant Food`.

- [ ] **Step 3: Create the migration**

```bash
docker compose run --rm web bin/rails generate migration CreateFoods
```

```ruby
class CreateFoods < ActiveRecord::Migration[8.1]
  def change
    create_table :foods, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.string :brand
      t.string :state, null: false
      t.decimal :kcal_per_100, precision: 8, scale: 2, null: false
      t.decimal :protein_per_100, precision: 8, scale: 2, null: false
      t.decimal :carbs_per_100, precision: 8, scale: 2, null: false
      t.decimal :fat_per_100, precision: 8, scale: 2, null: false
      t.decimal :fiber_per_100, precision: 8, scale: 2
      t.decimal :sodium_per_100, precision: 8, scale: 2
      t.decimal :sugar_per_100, precision: 8, scale: 2
      t.datetime :archived_at

      t.timestamps
    end

    add_index :foods, [ :user_id, :name ]
  end
end
```

- [ ] **Step 4: Write the model**

Create `app/models/food.rb`:

```ruby
class Food < ApplicationRecord
  # A food consumed in two states is two catalog records: raw and cooked
  # chicken differ by roughly 30%.
  STATES = %w[raw cooked dry as_sold].freeze
  MACRO_FIELDS = %i[kcal_per_100 protein_per_100 carbs_per_100 fat_per_100].freeze

  belongs_to :user
  has_many :servings, -> { order(:label) }, dependent: :destroy, inverse_of: :food
  has_many :entries, dependent: :nullify

  accepts_nested_attributes_for :servings, allow_destroy: true, reject_if: :all_blank

  validates :name, presence: true
  validates :state, presence: true, inclusion: { in: STATES }
  validates(*MACRO_FIELDS, presence: true, numericality: { greater_than_or_equal_to: 0 })
  validates :fiber_per_100, :sodium_per_100, :sugar_per_100,
    numericality: { greater_than_or_equal_to: 0, allow_nil: true }

  scope :active, -> { where(archived_at: nil) }

  def display_name
    brand.present? ? "#{name} (#{brand})" : name
  end

  def archived?
    archived_at.present?
  end
end
```

Add to `app/models/user.rb`, above the validations:

```ruby
  has_many :foods, dependent: :destroy
```

- [ ] **Step 5: Add the factory**

Create `spec/factories/foods.rb`:

```ruby
FactoryBot.define do
  factory :food do
    user
    name { "Port Salut light" }
    brand { "La Serenísima" }
    state { "as_sold" }
    kcal_per_100 { 220 }
    protein_per_100 { 27 }
    carbs_per_100 { 0 }
    fat_per_100 { 12 }
  end
end
```

- [ ] **Step 6: Migrate and run the test**

```bash
docker compose run --rm web bin/rails db:migrate
docker compose run --rm web bin/rspec spec/models/food_spec.rb
```

Expected: PASS. The `servings` association is declared but its table arrives in Task 4; the specs above do not exercise it, so they pass.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add the food catalog with per-100g values"
```

---

### Task 4: Servings

**Files:**
- Create: `db/migrate/<timestamp>_create_servings.rb`
- Create: `app/models/serving.rb`
- Create: `spec/factories/servings.rb`
- Test: `spec/models/serving_spec.rb`

**Interfaces:**
- Consumes: `Food` from Task 3.
- Produces: `Serving` with `label`, `grams`, `is_default`; `Food#servings`; `Food#default_serving`.

- [ ] **Step 1: Write the failing test**

Create `spec/models/serving_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Serving, type: :model do
  subject(:serving) { build(:serving) }

  it { is_expected.to belong_to(:food) }
  it { is_expected.to validate_presence_of(:label) }

  it "requires grams above zero" do
    expect(build(:serving, grams: 0)).not_to be_valid
    expect(build(:serving, grams: -5)).not_to be_valid
  end

  describe "the default serving" do
    let(:food) { create(:food) }

    it "clears the previous default when another is set" do
      first = create(:serving, food: food, label: "1 feta", is_default: true)
      second = create(:serving, food: food, label: "1 porción", is_default: true)

      expect(first.reload.is_default).to be(false)
      expect(second.reload.is_default).to be(true)
    end

    it "leaves other foods alone" do
      other_food_serving = create(:serving, is_default: true)
      create(:serving, food: food, is_default: true)

      expect(other_food_serving.reload.is_default).to be(true)
    end

    it "is exposed through Food#default_serving" do
      create(:serving, food: food, label: "1 feta", is_default: false)
      chosen = create(:serving, food: food, label: "1 porción", is_default: true)

      expect(food.reload.default_serving).to eq(chosen)
    end
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
docker compose run --rm web bin/rspec spec/models/serving_spec.rb
```

Expected: FAIL with `uninitialized constant Serving`.

- [ ] **Step 3: Create the migration**

```bash
docker compose run --rm web bin/rails generate migration CreateServings
```

```ruby
class CreateServings < ActiveRecord::Migration[8.1]
  def change
    create_table :servings, id: :uuid do |t|
      t.references :food, null: false, foreign_key: true, type: :uuid
      t.string :label, null: false
      t.decimal :grams, precision: 8, scale: 2, null: false
      t.boolean :is_default, null: false, default: false

      t.timestamps
    end
  end
end
```

- [ ] **Step 4: Write the model**

Create `app/models/serving.rb`:

```ruby
class Serving < ApplicationRecord
  belongs_to :food

  validates :label, presence: true
  validates :grams, numericality: { greater_than: 0 }

  after_save :clear_other_defaults, if: :is_default?

  private
    def clear_other_defaults
      food.servings.where.not(id: id).where(is_default: true).update_all(is_default: false)
    end
end
```

Add to `app/models/food.rb`, after the scopes:

```ruby
  def default_serving
    servings.find_by(is_default: true)
  end
```

- [ ] **Step 5: Add the factory**

Create `spec/factories/servings.rb`:

```ruby
FactoryBot.define do
  factory :serving do
    food
    label { "1 feta" }
    grams { 30 }
    is_default { false }
  end
end
```

- [ ] **Step 6: Migrate and run the test**

```bash
docker compose run --rm web bin/rails db:migrate
docker compose run --rm web bin/rspec spec/models/serving_spec.rb
```

Expected: PASS, 7 examples.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add servings as gram multipliers on a food"
```

---

### Task 5: MacroSplit and the Goal model

**Files:**
- Create: `app/models/macro_split.rb`
- Create: `db/migrate/<timestamp>_create_goals.rb`
- Create: `app/models/goal.rb`
- Modify: `app/models/user.rb`
- Create: `spec/factories/goals.rb`
- Test: `spec/models/macro_split_spec.rb`, `spec/models/goal_spec.rb`

**Interfaces:**
- Consumes: `User` from Task 2.
- Produces: `MacroSplit::PROTEIN_KCAL_PER_G` (4), `CARBS_KCAL_PER_G` (4), `FAT_KCAL_PER_G` (9), `DEFAULT_PERCENTAGES`; `MacroSplit.kcal_from(protein_g:, carbs_g:, fat_g:)` returning an Integer; `MacroSplit.percentages(protein_g:, carbs_g:, fat_g:)` returning `{protein:, carbs:, fat:}` of Floats; `MacroSplit.from_kcal(kcal)` returning `{protein_g:, carbs_g:, fat_g:}` of Integers. `Goal` with `label`, `kcal`, `protein_g`, `carbs_g`, `fat_g`, `is_default`, `effective_from`; `User#default_goal`.

- [ ] **Step 1: Write the failing MacroSplit test**

Create `spec/models/macro_split_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe MacroSplit, type: :model do
  describe ".kcal_from" do
    it "applies 4/4/9" do
      expect(MacroSplit.kcal_from(protein_g: 180, carbs_g: 220, fat_g: 78)).to eq(2302)
    end

    it "is zero for an empty split" do
      expect(MacroSplit.kcal_from(protein_g: 0, carbs_g: 0, fat_g: 0)).to eq(0)
    end

    it "treats nil as zero" do
      expect(MacroSplit.kcal_from(protein_g: 100, carbs_g: nil, fat_g: nil)).to eq(400)
    end
  end

  describe ".percentages" do
    it "reports each macro's share of the total" do
      result = MacroSplit.percentages(protein_g: 180, carbs_g: 220, fat_g: 78)

      expect(result[:protein]).to be_within(0.1).of(31.3)
      expect(result[:carbs]).to be_within(0.1).of(38.2)
      expect(result[:fat]).to be_within(0.1).of(30.5)
    end

    it "returns zeros rather than dividing by zero" do
      expect(MacroSplit.percentages(protein_g: 0, carbs_g: 0, fat_g: 0))
        .to eq(protein: 0.0, carbs: 0.0, fat: 0.0)
    end
  end

  describe ".from_kcal" do
    it "seeds a new goal at 25/50/25" do
      expect(MacroSplit.from_kcal(2500)).to eq(protein_g: 156, carbs_g: 313, fat_g: 69)
    end

    it "produces a split that reconstructs approximately the same total" do
      split = MacroSplit.from_kcal(2500)

      expect(MacroSplit.kcal_from(**split)).to be_within(10).of(2500)
    end

    it "is all zeros for a non-positive target" do
      expect(MacroSplit.from_kcal(0)).to eq(protein_g: 0, carbs_g: 0, fat_g: 0)
    end
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
docker compose run --rm web bin/rspec spec/models/macro_split_spec.rb
```

Expected: FAIL with `uninitialized constant MacroSplit`.

- [ ] **Step 3: Write MacroSplit**

Create `app/models/macro_split.rb`:

```ruby
# Converts between macro grams, calories and percentages. The arithmetic
# belongs to no single record: a Goal uses it to derive its calorie target, an
# ad-hoc Entry uses it to derive calories from typed macros, and the goal form
# uses it to seed a brand new split.
class MacroSplit
  PROTEIN_KCAL_PER_G = 4
  CARBS_KCAL_PER_G = 4
  FAT_KCAL_PER_G = 9

  # Inside the Institute of Medicine's Acceptable Macronutrient Distribution
  # Ranges (protein 10-35%, carbohydrate 45-65%, fat 20-35%), and landing
  # protein near 1.6 g/kg for a typical adult weight, where Morton et al.
  # (2018) found gains in fat-free mass plateau.
  DEFAULT_PERCENTAGES = { protein: 0.25, carbs: 0.50, fat: 0.25 }.freeze

  class << self
    def kcal_from(protein_g:, carbs_g:, fat_g:)
      (protein_g.to_f * PROTEIN_KCAL_PER_G +
        carbs_g.to_f * CARBS_KCAL_PER_G +
        fat_g.to_f * FAT_KCAL_PER_G).round
    end

    def percentages(protein_g:, carbs_g:, fat_g:)
      total = kcal_from(protein_g: protein_g, carbs_g: carbs_g, fat_g: fat_g)
      return { protein: 0.0, carbs: 0.0, fat: 0.0 } if total.zero?

      {
        protein: share(protein_g.to_f * PROTEIN_KCAL_PER_G, total),
        carbs: share(carbs_g.to_f * CARBS_KCAL_PER_G, total),
        fat: share(fat_g.to_f * FAT_KCAL_PER_G, total)
      }
    end

    def from_kcal(kcal)
      return { protein_g: 0, carbs_g: 0, fat_g: 0 } unless kcal.to_i.positive?

      {
        protein_g: (kcal * DEFAULT_PERCENTAGES[:protein] / PROTEIN_KCAL_PER_G).round,
        carbs_g: (kcal * DEFAULT_PERCENTAGES[:carbs] / CARBS_KCAL_PER_G).round,
        fat_g: (kcal * DEFAULT_PERCENTAGES[:fat] / FAT_KCAL_PER_G).round
      }
    end

    private
      def share(macro_kcal, total_kcal)
        (macro_kcal / total_kcal * 100).round(1)
      end
  end
end
```

- [ ] **Step 4: Run the MacroSplit test**

```bash
docker compose run --rm web bin/rspec spec/models/macro_split_spec.rb
```

Expected: PASS, 8 examples.

- [ ] **Step 5: Write the failing Goal test**

Create `spec/models/goal_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Goal, type: :model do
  subject(:goal) { build(:goal) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to validate_presence_of(:label) }

  it "rejects negative macros" do
    expect(build(:goal, protein_g: -1)).not_to be_valid
  end

  describe "kcal" do
    it "is always derived from the macros on save" do
      goal = create(:goal, protein_g: 180, carbs_g: 220, fat_g: 78, kcal: 9999)

      expect(goal.kcal).to eq(2302)
    end

    it "follows a macro change" do
      goal = create(:goal, protein_g: 144, carbs_g: 325, fat_g: 69)
      expect(goal.kcal).to eq(2497)

      goal.update!(protein_g: 180)

      expect(goal.kcal).to eq(2641)
    end
  end

  describe "#percentages" do
    it "delegates to MacroSplit" do
      goal = build(:goal, protein_g: 180, carbs_g: 220, fat_g: 78)

      expect(goal.percentages[:protein]).to be_within(0.1).of(31.3)
    end
  end

  describe "the default goal" do
    let(:user) { create(:user) }

    it "clears the previous default when another is set" do
      first = create(:goal, user: user, is_default: true)
      second = create(:goal, user: user, is_default: true)

      expect(first.reload.is_default).to be(false)
      expect(second.reload.is_default).to be(true)
    end

    it "is exposed through User#default_goal" do
      create(:goal, user: user, is_default: false)
      chosen = create(:goal, user: user, is_default: true)

      expect(user.reload.default_goal).to eq(chosen)
    end

    it "leaves other users alone" do
      other = create(:goal, is_default: true)
      create(:goal, user: user, is_default: true)

      expect(other.reload.is_default).to be(true)
    end
  end
end
```

- [ ] **Step 6: Run it to confirm it fails**

```bash
docker compose run --rm web bin/rspec spec/models/goal_spec.rb
```

Expected: FAIL with `uninitialized constant Goal`.

- [ ] **Step 7: Create the migration**

```bash
docker compose run --rm web bin/rails generate migration CreateGoals
```

```ruby
class CreateGoals < ActiveRecord::Migration[8.1]
  def change
    create_table :goals, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :label, null: false
      t.integer :kcal, null: false, default: 0
      t.integer :protein_g, null: false, default: 0
      t.integer :carbs_g, null: false, default: 0
      t.integer :fat_g, null: false, default: 0
      t.boolean :is_default, null: false, default: false
      t.date :effective_from, null: false

      t.timestamps
    end

    add_index :goals, [ :user_id, :effective_from ]
  end
end
```

- [ ] **Step 8: Write the model**

Create `app/models/goal.rb`:

```ruby
class Goal < ApplicationRecord
  MACRO_FIELDS = %i[protein_g carbs_g fat_g].freeze

  belongs_to :user
  has_many :day_logs, dependent: :restrict_with_error

  validates :label, presence: true
  validates :effective_from, presence: true
  validates(*MACRO_FIELDS, numericality: { greater_than_or_equal_to: 0 })

  # The calorie target is never entered directly: it is whatever the three
  # macros add up to. Moving any macro moves the total.
  before_validation :derive_kcal
  after_save :clear_other_defaults, if: :is_default?

  def percentages
    MacroSplit.percentages(protein_g: protein_g, carbs_g: carbs_g, fat_g: fat_g)
  end

  private
    def derive_kcal
      self.kcal = MacroSplit.kcal_from(protein_g: protein_g, carbs_g: carbs_g, fat_g: fat_g)
    end

    def clear_other_defaults
      user.goals.where.not(id: id).where(is_default: true).update_all(is_default: false)
    end
end
```

Add to `app/models/user.rb`, below `has_many :foods`:

```ruby
  has_many :goals, dependent: :destroy

  def default_goal
    goals.find_by(is_default: true)
  end
```

- [ ] **Step 9: Add the factory**

Create `spec/factories/goals.rb`:

```ruby
FactoryBot.define do
  factory :goal do
    user
    label { "Día normal" }
    protein_g { 156 }
    carbs_g { 313 }
    fat_g { 69 }
    is_default { true }
    effective_from { Date.current }
  end
end
```

- [ ] **Step 10: Migrate and run the tests**

```bash
docker compose run --rm web bin/rails db:migrate
docker compose run --rm web bin/rspec spec/models/goal_spec.rb spec/models/macro_split_spec.rb
```

Expected: PASS, 17 examples.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "Add MacroSplit and goals whose calorie target follows the macros"
```

---

### Task 6: DayLog and the 4 a.m. day boundary

**Files:**
- Create: `db/migrate/<timestamp>_create_day_logs.rb`
- Create: `app/models/day_log.rb`
- Modify: `app/models/user.rb`
- Create: `app/controllers/days_controller.rb`
- Create: `app/views/days/show.html.erb`
- Create: `spec/support/time_helpers.rb`
- Create: `spec/factories/day_logs.rb`
- Test: `spec/models/day_log_spec.rb`

**Interfaces:**
- Consumes: `User` from Task 2, `Goal` from Task 5.
- Produces: `DayLog.logical_date(user, time)` returning a `Date`; `DayLog.for(user, time = Time.current)` returning a persisted `DayLog` or raising when the user has no default goal; `DayLog::MissingGoal` error class; `User#day_logs`; a `DaysController#show` reachable at `root_path`.

- [ ] **Step 1: Add the time-travel helper**

Create `spec/support/time_helpers.rb`:

```ruby
RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers
end
```

- [ ] **Step 2: Write the failing test**

Create `spec/models/day_log_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe DayLog, type: :model do
  let(:user) { create(:user, day_cutoff_hour: 4) }
  let!(:goal) { create(:goal, user: user, is_default: true) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:goal) }

  describe ".logical_date" do
    it "counts 01:00 as the previous day" do
      time = Time.zone.local(2026, 9, 14, 1, 0)

      expect(DayLog.logical_date(user, time)).to eq(Date.new(2026, 9, 13))
    end

    it "counts 03:59 as the previous day" do
      time = Time.zone.local(2026, 9, 14, 3, 59)

      expect(DayLog.logical_date(user, time)).to eq(Date.new(2026, 9, 13))
    end

    it "counts 04:00 as the current day" do
      time = Time.zone.local(2026, 9, 14, 4, 0)

      expect(DayLog.logical_date(user, time)).to eq(Date.new(2026, 9, 14))
    end

    it "counts 23:00 as the current day" do
      time = Time.zone.local(2026, 9, 14, 23, 0)

      expect(DayLog.logical_date(user, time)).to eq(Date.new(2026, 9, 14))
    end

    it "honours a different cutoff hour" do
      midnight_user = create(:user, day_cutoff_hour: 0)
      time = Time.zone.local(2026, 9, 14, 1, 0)

      expect(DayLog.logical_date(midnight_user, time)).to eq(Date.new(2026, 9, 14))
    end
  end

  describe ".for" do
    it "creates the day and copies the user's default goal" do
      travel_to Time.zone.local(2026, 9, 14, 10, 0) do
        day_log = DayLog.for(user)

        expect(day_log.date).to eq(Date.new(2026, 9, 14))
        expect(day_log.goal).to eq(goal)
      end
    end

    it "returns the same record on a second call" do
      travel_to Time.zone.local(2026, 9, 14, 10, 0) do
        expect { 2.times { DayLog.for(user) } }.to change(DayLog, :count).by(1)
      end
    end

    it "keeps the goal that was in force even after the default changes" do
      travel_to Time.zone.local(2026, 9, 14, 10, 0) do
        day_log = DayLog.for(user)
        create(:goal, user: user, is_default: true, label: "Nueva")

        expect(day_log.reload.goal).to eq(goal)
      end
    end

    it "raises when the user has no default goal" do
      goal.update!(is_default: false)

      expect { DayLog.for(user) }.to raise_error(DayLog::MissingGoal)
    end
  end

  it "allows only one day log per user and date" do
    create(:day_log, user: user, goal: goal, date: Date.new(2026, 9, 14))
    duplicate = build(:day_log, user: user, goal: goal, date: Date.new(2026, 9, 14))

    expect(duplicate).not_to be_valid
  end
end
```

- [ ] **Step 3: Run it to confirm it fails**

```bash
docker compose run --rm web bin/rspec spec/models/day_log_spec.rb
```

Expected: FAIL with `uninitialized constant DayLog`.

- [ ] **Step 4: Create the migration**

```bash
docker compose run --rm web bin/rails generate migration CreateDayLogs
```

```ruby
class CreateDayLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :day_logs, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :goal, null: false, foreign_key: true, type: :uuid
      t.date :date, null: false

      t.timestamps
    end

    add_index :day_logs, [ :user_id, :date ], unique: true
  end
end
```

- [ ] **Step 5: Write the model**

Create `app/models/day_log.rb`:

```ruby
class DayLog < ApplicationRecord
  # Raised rather than silently creating a day without a target to measure
  # against. The controller turns this into a redirect to the goal form.
  class MissingGoal < StandardError; end

  belongs_to :user
  belongs_to :goal
  has_many :entries, -> { order(:meal, :position) }, dependent: :destroy, inverse_of: :day_log

  validates :date, presence: true, uniqueness: { scope: :user_id }

  class << self
    # The day does not end at midnight: food logged at 01:00 belongs to the
    # evening before. Shifting back by the cutoff and taking the date does it.
    def logical_date(user, time = Time.current)
      (time.in_time_zone(Time.zone) - user.day_cutoff_hour.hours).to_date
    end

    def for(user, time = Time.current)
      date = logical_date(user, time)
      existing = user.day_logs.find_by(date: date)
      return existing if existing

      goal = user.default_goal
      raise MissingGoal if goal.nil?

      user.day_logs.create!(date: date, goal: goal)
    end
  end

  def totals
    @totals ||= begin
      sums = entries.pick(
        Arel.sql("COALESCE(SUM(kcal), 0)"),
        Arel.sql("COALESCE(SUM(protein_g), 0)"),
        Arel.sql("COALESCE(SUM(carbs_g), 0)"),
        Arel.sql("COALESCE(SUM(fat_g), 0)")
      ) || [ 0, 0, 0, 0 ]

      { kcal: sums[0].to_f, protein_g: sums[1].to_f, carbs_g: sums[2].to_f, fat_g: sums[3].to_f }
    end
  end

  # May be negative, and is displayed that way. A day over the goal is
  # information, not an error to hide at zero.
  def remaining
    {
      kcal: goal.kcal - totals[:kcal],
      protein_g: goal.protein_g - totals[:protein_g],
      carbs_g: goal.carbs_g - totals[:carbs_g],
      fat_g: goal.fat_g - totals[:fat_g]
    }
  end

  def entries_for(meal)
    entries.select { |entry| entry.meal == meal }
  end
end
```

Add to `app/models/user.rb`:

```ruby
  has_many :day_logs, dependent: :destroy
```

- [ ] **Step 6: Add the factory**

Create `spec/factories/day_logs.rb`:

```ruby
FactoryBot.define do
  factory :day_log do
    user
    goal { association :goal, user: user }
    date { Date.current }
  end
end
```

- [ ] **Step 7: Migrate and run the test**

```bash
docker compose run --rm web bin/rails db:migrate
docker compose run --rm web bin/rspec spec/models/day_log_spec.rb
```

Expected: PASS, 12 examples.

- [ ] **Step 8: Replace the placeholder controller and view**

Task 2 left a stub at `root_path`. This gives it a real `DayLog`; Task 13 gives it the rings.

Replace `app/controllers/days_controller.rb`:

```ruby
class DaysController < ApplicationController
  rescue_from DayLog::MissingGoal, with: :redirect_to_goal

  def show
    @day_log = DayLog.for(current_user, requested_time)
  end

  private
    def requested_time
      return Time.current if params[:date].blank?

      Date.parse(params[:date]).in_time_zone(Time.zone).change(hour: 12)
    rescue Date::Error
      Time.current
    end

    def redirect_to_goal
      redirect_to edit_goal_path, notice: "Primero definí tu meta."
    end
end
```

Replace `app/views/days/show.html.erb`:

```erb
<h1><%= @day_log.date.to_fs(:iso8601) %></h1>
```

Plain ISO for now: the Spanish date format arrives with the locale file in Task 10.

Add to `config/routes.rb`, above `root`:

```ruby
  resource :goal, only: %i[edit update]
```

- [ ] **Step 9: Run the session tests**

```bash
docker compose run --rm web bin/rspec spec/requests/sessions_spec.rb spec/models/day_log_spec.rb
```

Expected: PASS. A signed-in user with no goal is redirected to `edit_goal_path`; that route exists from this task, and its controller arrives in Task 11.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "Add day logs with a configurable day boundary"
```

---

### Task 7: Entries with frozen macros

The heart of the spec. Read the "Entries" and "Calculation" sections of the design document before starting.

**Files:**
- Create: `db/migrate/<timestamp>_create_entries.rb`
- Create: `app/models/entry.rb`
- Create: `spec/factories/entries.rb`
- Test: `spec/models/entry_spec.rb`

**Interfaces:**
- Consumes: `Food` (Task 3), `DayLog` (Task 6), `MacroSplit` (Task 5).
- Produces: `Entry::MEALS` (`%w[breakfast lunch snack dinner]`); `Entry#from_catalog?`; `Entry#recalculate!`; `DayLog#entries`, `DayLog#totals`, `DayLog#remaining`, `DayLog#entries_for(meal)`.

- [ ] **Step 1: Write the failing test**

Create `spec/models/entry_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Entry, type: :model do
  let(:user) { create(:user) }
  let(:goal) { create(:goal, user: user, is_default: true) }
  let(:day_log) { create(:day_log, user: user, goal: goal) }

  # Port Salut light: 220 kcal, 27 protein, 0 carbs, 12 fat per 100 g
  let(:food) { create(:food, user: user, name: "Port Salut light", brand: "La Serenísima") }

  describe "a catalog entry" do
    it "computes its macros from the food and the weight" do
      entry = Entry.create!(day_log: day_log, food: food, meal: "snack", grams: 40)

      expect(entry.kcal).to eq(88.0)
      expect(entry.protein_g).to eq(10.8)
      expect(entry.carbs_g).to eq(0.0)
      expect(entry.fat_g).to eq(4.8)
    end

    it "snapshots the food name" do
      entry = Entry.create!(day_log: day_log, food: food, meal: "snack", grams: 40)

      expect(entry.food_name_snapshot).to eq("Port Salut light (La Serenísima)")
    end

    it "requires grams" do
      entry = build(:entry, day_log: day_log, food: food, grams: nil)

      expect(entry).not_to be_valid
      expect(entry.errors.attribute_names).to include(:grams)
    end

    it "rejects a weight of zero" do
      expect(build(:entry, day_log: day_log, food: food, grams: 0)).not_to be_valid
    end

    it "keeps its macros when the food is corrected afterwards" do
      entry = Entry.create!(day_log: day_log, food: food, meal: "snack", grams: 40)
      food.update!(protein_per_100: 50)

      expect(entry.reload.protein_g).to eq(10.8)
    end

    it "keeps its macros and name when the food is deleted" do
      entry = Entry.create!(day_log: day_log, food: food, meal: "snack", grams: 40)
      food.destroy

      entry.reload
      expect(entry.food_id).to be_nil
      expect(entry.food_name_snapshot).to eq("Port Salut light (La Serenísima)")
      expect(entry.protein_g).to eq(10.8)
    end

    it "picks up corrections only through an explicit recalculate!" do
      entry = Entry.create!(day_log: day_log, food: food, meal: "snack", grams: 40)
      food.update!(protein_per_100: 50)

      entry.recalculate!

      expect(entry.protein_g).to eq(20.0)
    end
  end

  describe "an ad-hoc entry" do
    it "derives calories from the typed macros" do
      entry = Entry.create!(
        day_log: day_log, meal: "dinner", food_name_snapshot: "Pizza muzza",
        protein_g: 100, carbs_g: 100, fat_g: 100
      )

      expect(entry.kcal).to eq(1700.0)
    end

    it "does not require a weight" do
      entry = build(:entry, :ad_hoc, day_log: day_log, grams: nil)

      expect(entry).to be_valid
    end

    it "requires a name" do
      entry = build(:entry, :ad_hoc, day_log: day_log, food_name_snapshot: nil)

      expect(entry).not_to be_valid
    end

    it "requires the three macros" do
      entry = build(:entry, :ad_hoc, day_log: day_log, protein_g: nil, carbs_g: nil, fat_g: nil)

      expect(entry).not_to be_valid
      expect(entry.errors.attribute_names).to include(:protein_g, :carbs_g, :fat_g)
    end
  end

  describe "validation of the meal" do
    it "rejects a meal outside the four" do
      expect { build(:entry, day_log: day_log, food: food, meal: "extra") }
        .to raise_error(ArgumentError)
    end
  end

  describe "day totals" do
    it "sums every entry in the day" do
      Entry.create!(day_log: day_log, food: food, meal: "snack", grams: 40)
      Entry.create!(day_log: day_log, food: food, meal: "dinner", grams: 60)

      expect(day_log.reload.totals[:kcal]).to eq(220.0)
      expect(day_log.totals[:protein_g]).to eq(27.0)
    end

    it "is zero for an empty day" do
      expect(day_log.totals).to eq(kcal: 0.0, protein_g: 0.0, carbs_g: 0.0, fat_g: 0.0)
    end

    it "reports a negative remainder when the goal is exceeded" do
      allow(goal).to receive(:kcal).and_return(100)
      Entry.create!(day_log: day_log, food: food, meal: "snack", grams: 100)

      expect(day_log.reload.remaining[:kcal]).to be_negative
    end
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
docker compose run --rm web bin/rspec spec/models/entry_spec.rb
```

Expected: FAIL with `uninitialized constant Entry`.

- [ ] **Step 3: Create the migration**

```bash
docker compose run --rm web bin/rails generate migration CreateEntries
```

```ruby
class CreateEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :entries, id: :uuid do |t|
      t.references :day_log, null: false, foreign_key: true, type: :uuid
      # Nullable: an ad-hoc entry has no catalog food, and deleting a food
      # must not take the history with it.
      t.references :food, foreign_key: { on_delete: :nullify }, type: :uuid
      t.string :meal, null: false
      t.decimal :grams, precision: 8, scale: 2
      t.string :serving_label
      t.string :food_name_snapshot, null: false
      t.decimal :kcal, precision: 8, scale: 2, null: false
      t.decimal :protein_g, precision: 8, scale: 2, null: false
      t.decimal :carbs_g, precision: 8, scale: 2, null: false
      t.decimal :fat_g, precision: 8, scale: 2, null: false
      t.integer :position, null: false, default: 0
      t.datetime :logged_at, null: false

      t.timestamps
    end

    add_index :entries, [ :day_log_id, :meal, :position ]
  end
end
```

- [ ] **Step 4: Write the model**

Create `app/models/entry.rb`:

```ruby
# An Entry is a historical fact, not a view onto the catalog. Its macros are
# computed once, at write time, and frozen. Correcting a food's values later
# must not rewrite what was eaten last month.
class Entry < ApplicationRecord
  MEALS = %w[breakfast lunch snack dinner].freeze

  belongs_to :day_log
  belongs_to :food, optional: true

  enum :meal, MEALS.index_with(&:itself), validate: true

  validates :food_name_snapshot, presence: true
  validates :grams, numericality: { greater_than: 0 }, if: :from_catalog?
  validates :grams, presence: true, if: :from_catalog?
  validates :protein_g, :carbs_g, :fat_g, presence: true, unless: :from_catalog?
  validates :kcal, :protein_g, :carbs_g, :fat_g,
    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  before_validation :set_logged_at
  before_validation :set_position, on: :create
  before_validation :snapshot_food_name
  before_validation :compute_macros

  # An entry loses its food_id when the food is deleted, so this asks about
  # the association as it stands right now.
  def from_catalog?
    food_id.present?
  end

  # The only way a stored entry's macros ever change.
  def recalculate!
    compute_macros
    save!
  end

  private
    def set_logged_at
      self.logged_at ||= Time.current
    end

    def set_position
      return if position.present? && position.positive?

      self.position = (day_log&.entries&.where(meal: meal)&.maximum(:position) || 0) + 1
    end

    def snapshot_food_name
      self.food_name_snapshot = food.display_name if food.present?
    end

    def compute_macros
      food.present? ? compute_from_food : compute_from_typed_macros
    end

    def compute_from_food
      return if grams.blank?

      factor = grams.to_d / 100
      self.kcal = (food.kcal_per_100 * factor).round(2)
      self.protein_g = (food.protein_per_100 * factor).round(2)
      self.carbs_g = (food.carbs_per_100 * factor).round(2)
      self.fat_g = (food.fat_per_100 * factor).round(2)
    end

    def compute_from_typed_macros
      self.kcal = MacroSplit.kcal_from(protein_g: protein_g, carbs_g: carbs_g, fat_g: fat_g)
    end
end
```

- [ ] **Step 5: Add the factory**

Create `spec/factories/entries.rb`:

```ruby
FactoryBot.define do
  factory :entry do
    day_log
    food { association :food, user: day_log.user }
    meal { "lunch" }
    grams { 100 }

    trait :ad_hoc do
      food { nil }
      food_name_snapshot { "Pizza muzza" }
      grams { nil }
      protein_g { 100 }
      carbs_g { 100 }
      fat_g { 100 }
    end
  end
end
```

- [ ] **Step 6: Migrate and run the test**

```bash
docker compose run --rm web bin/rails db:migrate
docker compose run --rm web bin/rspec spec/models/entry_spec.rb
```

Expected: PASS, 15 examples. If the "keeps its macros when the food is deleted" example fails with a foreign key violation, the `on_delete: :nullify` in the migration did not take — check it before changing the model.

- [ ] **Step 7: Run the whole suite and lint**

```bash
docker compose run --rm web bin/rspec
docker compose run --rm web bin/rubocop
```

Expected: all green.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Add entries whose macros are computed once and frozen"
```

---

### Task 8: Recently used foods

**Files:**
- Modify: `app/models/food.rb`
- Test: `spec/models/food_spec.rb`

**Interfaces:**
- Consumes: `Food` (Task 3), `Entry` (Task 7).
- Produces: `Food.recent_for(user, limit: 20)` returning an `ActiveRecord::Relation` of `Food`, most frequently and recently logged first; `Food.last_grams_for(user)` returning a `Hash` of food id (String) to grams (BigDecimal).

- [ ] **Step 1: Write the failing test**

Append to `spec/models/food_spec.rb`, inside the top-level describe:

```ruby
  describe ".recent_for" do
    let(:user) { create(:user) }
    let(:goal) { create(:goal, user: user, is_default: true) }
    let(:day_log) { create(:day_log, user: user, goal: goal) }

    it "ranks a more frequently logged food first" do
      rare = create(:food, user: user, name: "Rare")
      common = create(:food, user: user, name: "Common")

      create(:entry, day_log: day_log, food: rare, meal: "lunch")
      2.times { create(:entry, day_log: day_log, food: common, meal: "dinner") }

      expect(Food.recent_for(user).to_a).to eq([ common, rare ])
    end

    it "excludes another user's foods" do
      mine = create(:food, user: user, name: "Mine")
      create(:entry, day_log: day_log, food: mine, meal: "lunch")

      other_entry = create(:entry)

      expect(Food.recent_for(user)).to contain_exactly(mine)
      expect(Food.recent_for(user)).not_to include(other_entry.food)
    end

    it "excludes archived foods" do
      archived = create(:food, user: user, archived_at: Time.current)
      create(:entry, day_log: day_log, food: archived, meal: "lunch")

      expect(Food.recent_for(user)).to be_empty
    end

    it "honours the limit" do
      3.times do |n|
        food = create(:food, user: user, name: "Food #{n}")
        create(:entry, day_log: day_log, food: food, meal: "lunch")
      end

      expect(Food.recent_for(user, limit: 2).size).to eq(2)
    end

    it "is empty when nothing has been logged" do
      create(:food, user: user)

      expect(Food.recent_for(user)).to be_empty
    end
  end

  describe ".last_grams_for" do
    let(:user) { create(:user) }
    let(:goal) { create(:goal, user: user, is_default: true) }
    let(:day_log) { create(:day_log, user: user, goal: goal) }

    it "maps each food to the weight used the last time" do
      food = create(:food, user: user)
      create(:entry, day_log: day_log, food: food, meal: "lunch", grams: 150, logged_at: 2.days.ago)
      create(:entry, day_log: day_log, food: food, meal: "dinner", grams: 190, logged_at: 1.hour.ago)

      expect(Food.last_grams_for(user)[food.id]).to eq(190)
    end

    it "omits a food that has never been logged" do
      food = create(:food, user: user)

      expect(Food.last_grams_for(user)).not_to have_key(food.id)
    end

    it "ignores ad-hoc entries, which have no food" do
      create(:entry, :ad_hoc, day_log: day_log)

      expect(Food.last_grams_for(user)).to be_empty
    end

    it "excludes another user's entries" do
      create(:entry)

      expect(Food.last_grams_for(user)).to be_empty
    end
  end
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
docker compose run --rm web bin/rspec spec/models/food_spec.rb
```

Expected: FAIL with `undefined method 'recent_for'`.

- [ ] **Step 3: Implement the scopes**

Add to `app/models/food.rb`, after the `active` scope:

```ruby
  # Ordered by how often the food was logged recently, then by how recently.
  # This is the whole of the friction reduction in this iteration: the foods
  # eaten daily sit at the top of the entry form without a search.
  def self.recent_for(user, limit: 20)
    active
      .joins(entries: :day_log)
      .where(day_logs: { user_id: user.id })
      .group(:id)
      .order(Arel.sql("COUNT(entries.id) DESC, MAX(entries.logged_at) DESC"))
      .limit(limit)
  end

  # One row per food, carrying the weight used most recently. Prefilling the
  # entry form with it means a habitual 190 g of chicken is not retyped daily.
  def self.last_grams_for(user)
    Entry
      .joins(:day_log)
      .where(day_logs: { user_id: user.id })
      .where.not(food_id: nil)
      .order(:food_id, logged_at: :desc)
      .select("DISTINCT ON (entries.food_id) entries.food_id, entries.grams")
      .to_h { |entry| [ entry.food_id, entry.grams ] }
  end
```

- [ ] **Step 4: Run the test**

```bash
docker compose run --rm web bin/rspec spec/models/food_spec.rb
```

Expected: PASS. If Postgres complains that `entries.logged_at` must appear in GROUP BY, the aggregate is missing — it must be `MAX(entries.logged_at)`, not a bare column.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Rank foods by recent frequency and recall the last weight used"
```

---

### Task 9: Mobile-first layout and stylesheet foundation

Everything visual in Tasks 10-13 builds on the tokens and components defined here. No new behaviour.

**Files:**
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/assets/stylesheets/application.scss`
- Create: `app/assets/stylesheets/_tokens.scss`, `_base.scss`, `_components.scss`
- Create: `app/views/shared/_flash.html.erb`, `app/views/shared/_nav.html.erb`
- Test: `spec/requests/layout_spec.rb`

**Interfaces:**
- Consumes: `current_user` from Task 2.
- Produces: CSS custom properties `--color-bg`, `--color-surface`, `--color-text`, `--color-muted`, `--color-accent`, `--color-protein`, `--color-carbs`, `--color-fat`, `--space-1` through `--space-5`, `--radius`; classes `.button`, `.button--primary`, `.card`, `.field`, `.stack`, `.row`, `.nav`, `.flash`.

- [ ] **Step 1: Write the tokens**

Create `app/assets/stylesheets/_tokens.scss`:

```scss
:root {
  --color-bg: #12141a;
  --color-surface: #1c1f27;
  --color-text: #f2f4f8;
  --color-muted: #9aa1ae;
  --color-border: #2b2f3a;
  --color-accent: #4ade80;
  --color-danger: #f87171;

  --color-protein: #60a5fa;
  --color-carbs: #fbbf24;
  --color-fat: #f472b6;

  --space-1: 0.25rem;
  --space-2: 0.5rem;
  --space-3: 1rem;
  --space-4: 1.5rem;
  --space-5: 2.5rem;

  --radius: 0.75rem;
  --tap-target: 2.75rem;
}
```

- [ ] **Step 2: Write the base styles**

Create `app/assets/stylesheets/_base.scss`:

```scss
*,
*::before,
*::after {
  box-sizing: border-box;
}

body {
  margin: 0;
  padding: 0;
  background: var(--color-bg);
  color: var(--color-text);
  font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
  font-size: 16px;
  line-height: 1.5;
}

// Mobile first: one column with a comfortable gutter. Widened only above.
.container {
  width: 100%;
  max-width: 32rem;
  margin: 0 auto;
  padding: var(--space-3);
  padding-bottom: var(--space-5);
}

@media (min-width: 40rem) {
  .container {
    max-width: 40rem;
    padding-inline: var(--space-4);
  }
}

h1 {
  font-size: 1.5rem;
  margin: 0 0 var(--space-3);
}

a {
  color: var(--color-accent);
}
```

- [ ] **Step 3: Write the components**

Create `app/assets/stylesheets/_components.scss`:

```scss
.stack > * + * {
  margin-top: var(--space-3);
}

.row {
  display: flex;
  align-items: center;
  gap: var(--space-2);
}

.card {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius);
  padding: var(--space-3);
}

.button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-height: var(--tap-target);
  padding: 0 var(--space-3);
  border: 1px solid var(--color-border);
  border-radius: var(--radius);
  background: var(--color-surface);
  color: var(--color-text);
  font-size: 1rem;
  text-decoration: none;
  cursor: pointer;
}

.button--primary {
  background: var(--color-accent);
  border-color: var(--color-accent);
  color: #0b1f14;
  font-weight: 600;
}

.field {
  display: flex;
  flex-direction: column;
  gap: var(--space-1);

  label {
    color: var(--color-muted);
    font-size: 0.875rem;
  }

  input,
  select {
    min-height: var(--tap-target);
    padding: 0 var(--space-2);
    border: 1px solid var(--color-border);
    border-radius: var(--radius);
    background: var(--color-bg);
    color: var(--color-text);
    font-size: 1rem;
  }
}

.nav {
  display: flex;
  gap: var(--space-3);
  padding: var(--space-3);
  border-bottom: 1px solid var(--color-border);
}

.flash {
  padding: var(--space-2) var(--space-3);
  border-radius: var(--radius);
  background: var(--color-surface);
  border-left: 3px solid var(--color-accent);

  &--alert {
    border-left-color: var(--color-danger);
  }
}

.muted {
  color: var(--color-muted);
}

.negative {
  color: var(--color-danger);
}
```

- [ ] **Step 4: Wire them into the entrypoint**

Replace `app/assets/stylesheets/application.scss`:

```scss
@use "tokens";
@use "base";
@use "components";
```

- [ ] **Step 5: Write the shared partials**

Create `app/views/shared/_flash.html.erb`:

```erb
<% flash.each do |type, message| %>
  <div class="flash <%= "flash--alert" if type.to_s == "alert" %>"><%= message %></div>
<% end %>
```

Create `app/views/shared/_nav.html.erb`. The catalog link is added in Task 10, once `foods_path` exists — linking to it now would break every signed-in page:

```erb
<nav class="nav">
  <%= link_to "Hoy", root_path %>
  <%= link_to "Meta", edit_goal_path %>
  <%= button_to "Salir", sign_out_path, method: :delete, class: "button" %>
</nav>
```

- [ ] **Step 6: Update the layout**

Replace the `<body>` of `app/views/layouts/application.html.erb`:

```erb
  <body>
    <% if current_user %>
      <%= render "shared/nav" %>
    <% end %>

    <div class="container stack">
      <%= render "shared/flash" %>
      <%= yield %>
    </div>
  </body>
```

- [ ] **Step 7: Write the test**

Create `spec/requests/layout_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Layout", type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
  end

  it "hides the navigation from an anonymous visitor" do
    get sign_in_path

    expect(response.body).not_to include("Salir")
  end

  it "shows the navigation to a signed-in user" do
    sign_in_via_google(email: "a@example.com")
    create(:goal, user: User.last, is_default: true)

    get root_path

    expect(response.body).to include("Salir")
    expect(response.body).to include("Meta")
  end
end
```

- [ ] **Step 8: Run the test and build the stylesheet**

```bash
docker compose run --rm web bin/rspec spec/requests/layout_spec.rb
docker compose run --rm web bin/rails dartsass:build
```

Expected: PASS, 2 examples, and `app/assets/builds/application.css` contains the compiled tokens.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Add the mobile-first layout and stylesheet foundation"
```

---

### Task 10: Food catalog screens

**Files:**
- Create: `app/controllers/foods_controller.rb`
- Create: `app/views/foods/index.html.erb`, `new.html.erb`, `edit.html.erb`, `_form.html.erb`, `_food.html.erb`, `_serving_fields.html.erb`
- Modify: `config/routes.rb`
- Modify: `app/assets/stylesheets/_components.scss`
- Test: `spec/requests/foods_spec.rb`

**Interfaces:**
- Consumes: `Food` (Task 3), `Serving` (Task 4), layout (Task 9).
- Produces: `foods_path`, `new_food_path`, `edit_food_path(food)`; `FoodsController` scoped to `current_user`.

- [ ] **Step 1: Write the failing test**

Create `spec/requests/foods_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Foods", type: :request do
  let(:user) { create(:user, email: "a@example.com") }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
    sign_in_via_google(email: user.email, uid: user.uid)
  end

  it "lists only the signed-in user's active foods" do
    mine = create(:food, user: User.last, name: "Mi queso")
    create(:food, user: User.last, name: "Archivado", archived_at: Time.current)
    create(:food, name: "De otro")

    get foods_path

    expect(response.body).to include(mine.name)
    expect(response.body).not_to include("Archivado")
    expect(response.body).not_to include("De otro")
  end

  it "creates a food with a serving" do
    expect {
      post foods_path, params: {
        food: {
          name: "Port Salut light", brand: "La Serenísima", state: "as_sold",
          kcal_per_100: 220, protein_per_100: 27, carbs_per_100: 0, fat_per_100: 12,
          servings_attributes: { "0" => { label: "1 feta", grams: 30, is_default: "1" } }
        }
      }
    }.to change(Food, :count).by(1)

    food = Food.last
    expect(food.user).to eq(User.last)
    expect(food.servings.first.label).to eq("1 feta")
  end

  it "re-renders the form when the food is invalid" do
    post foods_path, params: { food: { name: "", state: "as_sold" } }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "updates a food" do
    food = create(:food, user: User.last)

    patch food_path(food), params: { food: { name: "Nuevo nombre" } }

    expect(food.reload.name).to eq("Nuevo nombre")
  end

  it "archives rather than deletes" do
    food = create(:food, user: User.last)

    delete food_path(food)

    expect(food.reload.archived_at).to be_present
    expect(Food.count).to eq(1)
  end

  it "refuses to touch another user's food" do
    other = create(:food)

    expect { get edit_food_path(other) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
docker compose run --rm web bin/rspec spec/requests/foods_spec.rb
```

Expected: FAIL — `foods_path` is undefined.

- [ ] **Step 3: Add the routes**

In `config/routes.rb`, above `root`:

```ruby
  resources :foods
```

- [ ] **Step 4: Write the controller**

Create `app/controllers/foods_controller.rb`:

```ruby
class FoodsController < ApplicationController
  before_action :set_food, only: %i[edit update destroy]

  def index
    @foods = current_user.foods.active.order(:name)
  end

  def new
    @food = current_user.foods.build(state: "as_sold")
    @food.servings.build
  end

  def create
    @food = current_user.foods.build(food_params)

    if @food.save
      redirect_to foods_path, notice: "Alimento guardado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @food.servings.build if @food.servings.empty?
  end

  def update
    if @food.update(food_params)
      redirect_to foods_path, notice: "Alimento actualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Soft delete: entries reference this food, and the catalog is history too.
  def destroy
    @food.update!(archived_at: Time.current)
    redirect_to foods_path, notice: "Alimento archivado."
  end

  private
    def set_food
      @food = current_user.foods.find(params[:id])
    end

    def food_params
      params.require(:food).permit(
        :name, :brand, :state,
        :kcal_per_100, :protein_per_100, :carbs_per_100, :fat_per_100,
        :fiber_per_100, :sodium_per_100, :sugar_per_100,
        servings_attributes: %i[id label grams is_default _destroy]
      )
    end
end
```

- [ ] **Step 5: Write the views**

Create `app/views/foods/index.html.erb`:

```erb
<% content_for :title, "Alimentos" %>

<div class="row" style="justify-content: space-between;">
  <h1>Alimentos</h1>
  <%= link_to "Nuevo", new_food_path, class: "button button--primary" %>
</div>

<div class="stack">
  <% if @foods.empty? %>
    <p class="muted">Todavía no cargaste ningún alimento.</p>
  <% end %>
  <%= render @foods %>
</div>
```

Create `app/views/foods/_food.html.erb`:

```erb
<div class="card">
  <div class="row" style="justify-content: space-between;">
    <div>
      <strong><%= food.display_name %></strong>
      <div class="muted"><%= t("food.states.#{food.state}") %> · por 100 g</div>
    </div>
    <%= link_to "Editar", edit_food_path(food) %>
  </div>
  <div class="muted">
    <%= number_with_precision(food.kcal_per_100, precision: 0) %> kcal ·
    P <%= number_with_precision(food.protein_per_100, precision: 1) %> ·
    C <%= number_with_precision(food.carbs_per_100, precision: 1) %> ·
    G <%= number_with_precision(food.fat_per_100, precision: 1) %>
  </div>
</div>
```

Create `app/views/foods/new.html.erb`:

```erb
<% content_for :title, "Nuevo alimento" %>
<h1>Nuevo alimento</h1>
<%= render "form", food: @food %>
```

Create `app/views/foods/edit.html.erb`:

```erb
<% content_for :title, "Editar alimento" %>
<h1>Editar alimento</h1>
<%= render "form", food: @food %>
<%= button_to "Archivar", food_path(@food), method: :delete, class: "button" %>
```

Create `app/views/foods/_form.html.erb`:

```erb
<%= form_with model: food, class: "stack" do |form| %>
  <% if food.errors.any? %>
    <div class="flash flash--alert">
      <%= food.errors.full_messages.to_sentence %>
    </div>
  <% end %>

  <div class="field">
    <%= form.label :name, "Nombre" %>
    <%= form.text_field :name %>
  </div>

  <div class="field">
    <%= form.label :brand, "Marca (opcional)" %>
    <%= form.text_field :brand %>
  </div>

  <div class="field">
    <%= form.label :state, "Estado" %>
    <%= form.select :state, Food::STATES.map { |state| [ t("food.states.#{state}"), state ] } %>
  </div>

  <p class="muted">Valores de la etiqueta, por cada 100 g.</p>

  <div class="field">
    <%= form.label :kcal_per_100, "Calorías" %>
    <%= form.number_field :kcal_per_100, step: :any, inputmode: "decimal" %>
  </div>

  <div class="field">
    <%= form.label :protein_per_100, "Proteína (g)" %>
    <%= form.number_field :protein_per_100, step: :any, inputmode: "decimal" %>
  </div>

  <div class="field">
    <%= form.label :carbs_per_100, "Carbohidratos (g)" %>
    <%= form.number_field :carbs_per_100, step: :any, inputmode: "decimal" %>
  </div>

  <div class="field">
    <%= form.label :fat_per_100, "Grasa (g)" %>
    <%= form.number_field :fat_per_100, step: :any, inputmode: "decimal" %>
  </div>

  <h2>Porciones</h2>
  <p class="muted">Por ejemplo "1 feta" equivale a 30 g.</p>
  <%= form.fields_for :servings do |serving_form| %>
    <%= render "serving_fields", form: serving_form %>
  <% end %>

  <%= form.submit "Guardar", class: "button button--primary" %>
<% end %>
```

Create `app/views/foods/_serving_fields.html.erb`:

```erb
<div class="card stack">
  <div class="field">
    <%= form.label :label, "Etiqueta" %>
    <%= form.text_field :label %>
  </div>
  <div class="field">
    <%= form.label :grams, "Gramos" %>
    <%= form.number_field :grams, step: :any, inputmode: "decimal" %>
  </div>
  <label class="row">
    <%= form.check_box :is_default %>
    Preseleccionar esta porción
  </label>
</div>
```

- [ ] **Step 6: Add the state translations**

Create `config/locales/es.yml`:

```yaml
es:
  food:
    states:
      raw: "Crudo"
      cooked: "Cocido"
      dry: "Seco"
      as_sold: "Tal como se vende"
  meals:
    breakfast: "Desayuno"
    lunch: "Almuerzo"
    snack: "Merienda"
    dinner: "Cena"
  date:
    formats:
      long: "%A %-d de %B de %Y"
    day_names: [domingo, lunes, martes, miércoles, jueves, viernes, sábado]
    month_names: [~, enero, febrero, marzo, abril, mayo, junio, julio, agosto, septiembre, octubre, noviembre, diciembre]
```

The date section matters here and not later: this step makes `:es` the default locale, and Rails ships no Spanish date formats. Any view calling `l date, format: :long` would raise a missing-translation error from this point on.

Add the catalog link to `app/views/shared/_nav.html.erb`, after the "Hoy" link:

```erb
  <%= link_to "Alimentos", foods_path %>
```

In `config/application.rb`, inside the `Application` class:

```ruby
    config.i18n.default_locale = :es
    config.i18n.available_locales = [ :es, :en ]
```

- [ ] **Step 7: Run the test**

```bash
docker compose run --rm web bin/rspec spec/requests/foods_spec.rb
```

Expected: PASS, 6 examples.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Add the food catalog screens with nested servings"
```

---

### Task 11: The goal calculator

**Files:**
- Create: `app/controllers/goals_controller.rb`
- Create: `app/views/goals/edit.html.erb`
- Create: `app/javascript/controllers/macro_calculator_controller.js`
- Modify: `app/assets/stylesheets/_components.scss`
- Test: `spec/requests/goals_spec.rb`

**Interfaces:**
- Consumes: `Goal`, `MacroSplit` (Task 5).
- Produces: `edit_goal_path`, `goal_path`; a Stimulus controller registered as `macro-calculator` with targets `protein`, `carbs`, `fat`, `kcal`, `proteinPct`, `carbsPct`, `fatPct` and action `recalculate`.

- [ ] **Step 1: Write the failing test**

Create `spec/requests/goals_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Goals", type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
    sign_in_via_google(email: "a@example.com")
  end

  def user = User.last

  it "seeds a first goal at 25/50/25 from a calorie figure" do
    get edit_goal_path, params: { kcal: 2500 }

    expect(response.body).to include("156")
    expect(response.body).to include("313")
    expect(response.body).to include("69")
  end

  it "starts blank when no calorie figure is given" do
    get edit_goal_path

    expect(response).to have_http_status(:ok)
  end

  it "creates the goal on first save and marks it default" do
    expect {
      patch goal_path, params: { goal: { label: "Día normal", protein_g: 180, carbs_g: 220, fat_g: 78 } }
    }.to change(Goal, :count).by(1)

    goal = user.default_goal
    expect(goal.kcal).to eq(2302)
    expect(goal.is_default).to be(true)
  end

  it "updates the existing goal in place rather than versioning on every edit" do
    patch goal_path, params: { goal: { label: "Día normal", protein_g: 180, carbs_g: 220, fat_g: 78 } }

    expect {
      patch goal_path, params: { goal: { label: "Día normal", protein_g: 190, carbs_g: 220, fat_g: 78 } }
    }.not_to change(Goal, :count)

    expect(user.default_goal.kcal).to eq(2342)
  end

  it "re-renders when the macros are invalid" do
    patch goal_path, params: { goal: { label: "", protein_g: -5 } }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "redirects to the day after saving" do
    patch goal_path, params: { goal: { label: "Día normal", protein_g: 180, carbs_g: 220, fat_g: 78 } }

    expect(response).to redirect_to(root_path)
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
docker compose run --rm web bin/rspec spec/requests/goals_spec.rb
```

Expected: FAIL — `GoalsController` is missing.

- [ ] **Step 3: Write the controller**

Create `app/controllers/goals_controller.rb`:

```ruby
class GoalsController < ApplicationController
  def edit
    @goal = current_user.default_goal || build_seeded_goal
  end

  def update
    @goal = current_user.default_goal || current_user.goals.build(effective_from: Date.current, is_default: true)

    if @goal.update(goal_params)
      redirect_to root_path, notice: "Meta guardada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    # A brand new goal has no split to preserve. Seeding from a calorie figure
    # uses MacroSplit's evidence-backed default rather than leaving the form
    # blank; the user overwrites it from there.
    def build_seeded_goal
      seed = MacroSplit.from_kcal(params[:kcal].to_i)

      current_user.goals.build(
        label: "Día normal",
        effective_from: Date.current,
        is_default: true,
        **seed
      )
    end

    def goal_params
      params.require(:goal).permit(:label, :protein_g, :carbs_g, :fat_g)
    end
end
```

- [ ] **Step 4: Write the Stimulus controller**

Create `app/javascript/controllers/macro_calculator_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Mirrors MacroSplit so the calorie total and the three percentages respond as
// the user types. The server recomputes on save, so this is display only.
const PROTEIN_KCAL_PER_G = 4
const CARBS_KCAL_PER_G = 4
const FAT_KCAL_PER_G = 9

export default class extends Controller {
  static targets = ["protein", "carbs", "fat", "kcal", "proteinPct", "carbsPct", "fatPct"]

  connect() {
    this.recalculate()
  }

  recalculate() {
    const protein = this.gramsFrom(this.proteinTarget)
    const carbs = this.gramsFrom(this.carbsTarget)
    const fat = this.gramsFrom(this.fatTarget)

    const proteinKcal = protein * PROTEIN_KCAL_PER_G
    const carbsKcal = carbs * CARBS_KCAL_PER_G
    const fatKcal = fat * FAT_KCAL_PER_G
    const total = proteinKcal + carbsKcal + fatKcal

    this.kcalTarget.textContent = Math.round(total)
    this.proteinPctTarget.textContent = this.percentage(proteinKcal, total)
    this.carbsPctTarget.textContent = this.percentage(carbsKcal, total)
    this.fatPctTarget.textContent = this.percentage(fatKcal, total)
  }

  gramsFrom(element) {
    const value = parseFloat(element.value)
    return Number.isFinite(value) ? value : 0
  }

  percentage(macroKcal, totalKcal) {
    if (totalKcal === 0) return "0"
    return (macroKcal / totalKcal * 100).toFixed(0)
  }
}
```

- [ ] **Step 5: Write the view**

Create `app/views/goals/edit.html.erb`:

```erb
<% content_for :title, "Meta" %>
<h1>Meta diaria</h1>

<%= form_with model: @goal, url: goal_path, method: :patch, class: "stack",
      data: { controller: "macro-calculator", action: "input->macro-calculator#recalculate" } do |form| %>

  <% if @goal.errors.any? %>
    <div class="flash flash--alert"><%= @goal.errors.full_messages.to_sentence %></div>
  <% end %>

  <div class="card goal-total">
    <span class="goal-total__value" data-macro-calculator-target="kcal">0</span>
    <span class="muted">kcal objetivo</span>
  </div>

  <div class="field">
    <%= form.label :label, "Nombre" %>
    <%= form.text_field :label %>
  </div>

  <div class="field">
    <%= form.label :protein_g, "Proteína (g)" %>
    <%= form.number_field :protein_g, step: 1, inputmode: "numeric",
          data: { macro_calculator_target: "protein" } %>
    <span class="muted"><span data-macro-calculator-target="proteinPct">0</span>% de las calorías</span>
  </div>

  <div class="field">
    <%= form.label :carbs_g, "Carbohidratos (g)" %>
    <%= form.number_field :carbs_g, step: 1, inputmode: "numeric",
          data: { macro_calculator_target: "carbs" } %>
    <span class="muted"><span data-macro-calculator-target="carbsPct">0</span>% de las calorías</span>
  </div>

  <div class="field">
    <%= form.label :fat_g, "Grasa (g)" %>
    <%= form.number_field :fat_g, step: 1, inputmode: "numeric",
          data: { macro_calculator_target: "fat" } %>
    <span class="muted"><span data-macro-calculator-target="fatPct">0</span>% de las calorías</span>
  </div>

  <p class="muted">
    Movés cualquiera de los tres y las calorías se recalculan solas.
  </p>

  <%= form.submit "Guardar meta", class: "button button--primary" %>
<% end %>
```

- [ ] **Step 6: Add the total styling**

Append to `app/assets/stylesheets/_components.scss`:

```scss
.goal-total {
  text-align: center;

  &__value {
    display: block;
    font-size: 2.5rem;
    font-weight: 700;
    line-height: 1.1;
  }
}
```

- [ ] **Step 7: Run the test**

```bash
docker compose run --rm web bin/rspec spec/requests/goals_spec.rb
```

Expected: PASS, 6 examples.

- [ ] **Step 8: Verify the live arithmetic in the browser**

```bash
docker compose up -d
```

Open `http://localhost:3000/goal/edit`, change the protein field, and confirm the calorie total and the three percentages update without a page reload. The Stimulus controller is display-only, so if it fails the form still saves correctly — but it is the whole point of the screen, so do not skip this check.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Add the goal calculator with live calorie and percentage feedback"
```

---

### Task 12: Logging entries

The screen used several times a day. The form stays open after each save so a multi-item meal is logged without renavigating.

**Files:**
- Create: `app/controllers/entries_controller.rb`
- Create: `app/views/entries/new.html.erb`, `_form.html.erb`, `_entry.html.erb`, `create.turbo_stream.erb`
- Create: `app/javascript/controllers/entry_preview_controller.js`
- Modify: `config/routes.rb`
- Test: `spec/requests/entries_spec.rb`

**Interfaces:**
- Consumes: `Entry` (Task 7), `Food.recent_for` and `Food.last_grams_for` (Task 8), `DayLog.for` (Task 6). `Food.last_grams_for(user)` returns a Hash keyed by food id; the form puts each value on its option so the weight field prefills on selection.
- Produces: `new_entry_path`, `entries_path`, `entry_path(entry)`; a Stimulus controller registered as `entry-preview`.

- [ ] **Step 1: Write the failing test**

Create `spec/requests/entries_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Entries", type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
    sign_in_via_google(email: "a@example.com")
    create(:goal, user: User.last, is_default: true)
  end

  def user = User.last

  it "logs a catalog food by weight" do
    food = create(:food, user: user)

    expect {
      post entries_path, params: { entry: { food_id: food.id, meal: "lunch", grams: 40 } }
    }.to change(Entry, :count).by(1)

    entry = Entry.last
    expect(entry.protein_g).to eq(10.8)
    expect(entry.day_log.user).to eq(user)
  end

  it "resolves a serving into grams" do
    food = create(:food, user: user)
    serving = create(:serving, food: food, label: "1 feta", grams: 30)

    post entries_path, params: { entry: { food_id: food.id, meal: "snack", serving_id: serving.id, quantity: 2 } }

    entry = Entry.last
    expect(entry.grams).to eq(60)
    expect(entry.serving_label).to eq("2 × 1 feta")
  end

  it "logs an ad-hoc entry from typed macros" do
    post entries_path, params: {
      entry: { meal: "dinner", food_name_snapshot: "Pizza muzza", protein_g: 100, carbs_g: 100, fat_g: 100 }
    }

    expect(Entry.last.kcal).to eq(1700)
    expect(Entry.last.food_id).to be_nil
  end

  it "answers a Turbo Stream request without leaving the form" do
    food = create(:food, user: user)

    post entries_path,
      params: { entry: { food_id: food.id, meal: "lunch", grams: 40 } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include("turbo-stream")
  end

  it "refuses a food belonging to someone else" do
    other_food = create(:food)

    expect {
      post entries_path, params: { entry: { food_id: other_food.id, meal: "lunch", grams: 40 } }
    }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "deletes an entry" do
    food = create(:food, user: user)
    post entries_path, params: { entry: { food_id: food.id, meal: "lunch", grams: 40 } }
    entry = Entry.last

    expect { delete entry_path(entry) }.to change(Entry, :count).by(-1)
  end

  it "shows recently logged foods on the form" do
    food = create(:food, user: user, name: "Pechuga de pollo")
    post entries_path, params: { entry: { food_id: food.id, meal: "lunch", grams: 190 } }

    get new_entry_path

    expect(response.body).to include("Pechuga de pollo")
  end

  it "carries the last weight used onto the food option" do
    food = create(:food, user: user, name: "Pechuga de pollo")
    post entries_path, params: { entry: { food_id: food.id, meal: "lunch", grams: 190 } }

    get new_entry_path

    expect(response.body).to include("data-last-grams=\"190.0\"")
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
docker compose run --rm web bin/rspec spec/requests/entries_spec.rb
```

Expected: FAIL — `entries_path` is undefined.

- [ ] **Step 3: Add the routes**

In `config/routes.rb`, above `root`:

```ruby
  resources :entries, only: %i[new create destroy]
```

- [ ] **Step 4: Write the controller**

Create `app/controllers/entries_controller.rb`:

```ruby
class EntriesController < ApplicationController
  rescue_from DayLog::MissingGoal, with: :redirect_to_goal

  def new
    @day_log = DayLog.for(current_user)
    @entry = Entry.new(meal: params[:meal].presence || "breakfast")
    load_food_options
  end

  def create
    @day_log = DayLog.for(current_user)
    @entry = @day_log.entries.build(entry_attributes)

    if @entry.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to new_entry_path(meal: @entry.meal), notice: "Registrado." }
      end
    else
      load_food_options
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    entry = Entry.joins(:day_log).where(day_logs: { user_id: current_user.id }).find(params[:id])
    entry.destroy
    redirect_back fallback_location: root_path, notice: "Entrada eliminada."
  end

  private
    def load_food_options
      @recent_foods = Food.recent_for(current_user)
      @last_grams = Food.last_grams_for(current_user)
    end

    def entry_attributes
      attributes = entry_params.except(:serving_id, :quantity)
      food = find_food(entry_params[:food_id])
      return attributes.merge(food: nil) if food.nil?

      attributes.merge(food: food, **serving_resolution(food))
    end

    # A serving is a multiplier, never a source of macros: it resolves to
    # grams and the macros follow from the food's per-100 g values.
    def serving_resolution(food)
      serving = food.servings.find_by(id: entry_params[:serving_id])
      return {} if serving.nil?

      quantity = entry_params[:quantity].to_d
      quantity = 1 if quantity.zero?

      { grams: serving.grams * quantity, serving_label: "#{quantity.to_i} × #{serving.label}" }
    end

    def find_food(food_id)
      return nil if food_id.blank?

      current_user.foods.find(food_id)
    end

    def entry_params
      params.require(:entry).permit(
        :food_id, :meal, :grams, :serving_id, :quantity,
        :food_name_snapshot, :protein_g, :carbs_g, :fat_g
      )
    end

    def redirect_to_goal
      redirect_to edit_goal_path, notice: "Primero definí tu meta."
    end
end
```

- [ ] **Step 5: Write the preview Stimulus controller**

Create `app/javascript/controllers/entry_preview_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Shows the macros a weight will produce, before the entry is saved. The
// per-100 g values ride along on the selected option.
export default class extends Controller {
  static targets = ["food", "grams", "kcal", "protein", "carbs", "fat"]

  connect() {
    this.preview()
  }

  // Selecting a food prefills the weight used last time, so a habitual
  // portion is not retyped. A weight already typed is left alone.
  foodChanged() {
    const option = this.foodTarget.selectedOptions[0]
    const lastGrams = option && option.dataset.lastGrams

    if (lastGrams && this.gramsTarget.value === "") {
      this.gramsTarget.value = parseFloat(lastGrams)
    }

    this.preview()
  }

  preview() {
    const option = this.foodTarget.selectedOptions[0]
    const grams = parseFloat(this.gramsTarget.value)

    if (!option || !option.dataset.kcal || !Number.isFinite(grams)) {
      this.render(0, 0, 0, 0)
      return
    }

    const factor = grams / 100
    this.render(
      option.dataset.kcal * factor,
      option.dataset.protein * factor,
      option.dataset.carbs * factor,
      option.dataset.fat * factor
    )
  }

  render(kcal, protein, carbs, fat) {
    this.kcalTarget.textContent = Math.round(kcal)
    this.proteinTarget.textContent = protein.toFixed(1)
    this.carbsTarget.textContent = carbs.toFixed(1)
    this.fatTarget.textContent = fat.toFixed(1)
  }
}
```

- [ ] **Step 6: Write the views**

Create `app/views/entries/new.html.erb`:

```erb
<% content_for :title, "Agregar comida" %>
<h1>Agregar</h1>

<%= render "form", entry: @entry, recent_foods: @recent_foods, last_grams: @last_grams %>

<h2>Registrado hoy</h2>
<div id="logged_entries" class="stack">
  <%= render @day_log.entries %>
</div>
```

Create `app/views/entries/_form.html.erb`:

```erb
<%= form_with model: entry, url: entries_path, class: "stack",
      data: { controller: "entry-preview", action: "input->entry-preview#preview change->entry-preview#preview" } do |form| %>

  <% if entry.errors.any? %>
    <div class="flash flash--alert"><%= entry.errors.full_messages.to_sentence %></div>
  <% end %>

  <div class="field">
    <%= form.label :meal, "Comida" %>
    <%= form.select :meal, Entry::MEALS.map { |meal| [ t("meals.#{meal}"), meal ] } %>
  </div>

  <div class="field">
    <%= form.label :food_id, "Alimento" %>
    <%= form.select :food_id,
          recent_foods.map { |food|
            [ food.display_name, food.id, {
              data: {
                kcal: food.kcal_per_100, protein: food.protein_per_100,
                carbs: food.carbs_per_100, fat: food.fat_per_100,
                last_grams: last_grams[food.id]
              }
            } ]
          },
          { include_blank: "Elegí un alimento" },
          data: { entry_preview_target: "food", action: "change->entry-preview#foodChanged" } %>
  </div>

  <div class="field">
    <%= form.label :grams, "Peso (g)" %>
    <%= form.number_field :grams, step: :any, inputmode: "decimal",
          data: { entry_preview_target: "grams" } %>
  </div>

  <div class="card">
    <strong><span data-entry-preview-target="kcal">0</span> kcal</strong>
    <div class="muted">
      P <span data-entry-preview-target="protein">0</span> ·
      C <span data-entry-preview-target="carbs">0</span> ·
      G <span data-entry-preview-target="fat">0</span>
    </div>
  </div>

  <%= form.submit "Agregar", class: "button button--primary" %>
<% end %>

<p><%= link_to "Cargar algo que no está en el catálogo", new_entry_path(ad_hoc: true) %></p>
```

Create `app/views/entries/_entry.html.erb`:

```erb
<div class="card row" style="justify-content: space-between;" id="<%= dom_id(entry) %>">
  <div>
    <strong><%= entry.food_name_snapshot %></strong>
    <div class="muted">
      <%= entry.serving_label.presence || (entry.grams ? "#{number_with_precision(entry.grams, precision: 0)} g" : "—") %> ·
      <%= number_with_precision(entry.kcal, precision: 0) %> kcal ·
      P <%= number_with_precision(entry.protein_g, precision: 1) %> ·
      C <%= number_with_precision(entry.carbs_g, precision: 1) %> ·
      G <%= number_with_precision(entry.fat_g, precision: 1) %>
    </div>
  </div>
  <%= button_to "Borrar", entry_path(entry), method: :delete, class: "button" %>
</div>
```

Create `app/views/entries/create.turbo_stream.erb`:

```erb
<%= turbo_stream.append "logged_entries" do %>
  <%= render @entry %>
<% end %>
```

- [ ] **Step 7: Run the test**

```bash
docker compose run --rm web bin/rspec spec/requests/entries_spec.rb
```

Expected: PASS, 8 examples.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Add entry logging that keeps the form open between items"
```

---

### Task 13: The day dashboard

**Files:**
- Replace: `app/views/days/show.html.erb`
- (`app/controllers/days_controller.rb` is already correct from Task 6 — this task changes the view only)
- Create: `app/views/days/_ring.html.erb`, `app/views/days/_meal.html.erb`
- Create: `app/helpers/days_helper.rb`
- Modify: `app/assets/stylesheets/_components.scss`
- Test: `spec/helpers/days_helper_spec.rb` (create), `spec/requests/days_spec.rb` (extend — Task 6's fix round created it)

**Interfaces:**
- Consumes: `DayLog#totals`, `#remaining`, `#entries_for` (Task 6), `Entry::MEALS` (Task 7).
- Produces: `DaysHelper#ring_dash_array(current, goal, circumference)` returning a String.

- [ ] **Step 1: Write the failing helper test**

Create `spec/helpers/days_helper_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe DaysHelper, type: :helper do
  describe "#ring_dash_array" do
    it "fills half the ring at half the goal" do
      expect(helper.ring_dash_array(50, 100, 100)).to eq("50.0 100")
    end

    it "fills nothing at zero" do
      expect(helper.ring_dash_array(0, 100, 100)).to eq("0.0 100")
    end

    it "caps the arc at a full ring when the goal is exceeded" do
      expect(helper.ring_dash_array(150, 100, 100)).to eq("100.0 100")
    end

    it "fills nothing when the goal is zero rather than dividing by it" do
      expect(helper.ring_dash_array(50, 0, 100)).to eq("0.0 100")
    end
  end
end
```

- [ ] **Step 2: Write the failing request test**

`spec/requests/days_spec.rb` already exists from Task 6's fix round, covering the missing-goal redirect and hostile `params[:date]` input. ADD the dashboard examples below to it; do not overwrite what is there:

```ruby
require "rails_helper"

RSpec.describe "Days", type: :request do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
    sign_in_via_google(email: "a@example.com")
  end

  def user = User.last

  it "sends a user with no goal to the calculator" do
    get root_path

    expect(response).to redirect_to(edit_goal_path)
  end

  context "with a goal" do
    let!(:goal) { create(:goal, user: User.last, is_default: true, protein_g: 156, carbs_g: 313, fat_g: 69) }

    it "shows the goal total" do
      get root_path

      expect(response.body).to include(goal.kcal.to_s)
    end

    it "groups entries under their meal" do
      food = create(:food, user: user, name: "Pechuga de pollo")
      post entries_path, params: { entry: { food_id: food.id, meal: "lunch", grams: 190 } }

      get root_path

      expect(response.body).to include("Almuerzo")
      expect(response.body).to include("Pechuga de pollo")
    end

    it "shows a negative remainder rather than clamping at zero" do
      food = create(:food, user: user, kcal_per_100: 1000, protein_per_100: 0, carbs_per_100: 0, fat_per_100: 0)
      post entries_path, params: { entry: { food_id: food.id, meal: "dinner", grams: 1000 } }

      get root_path

      expect(response.body).to include("-")
      expect(response.body).to include("negative")
    end

    it "navigates to another date" do
      get root_path, params: { date: "2026-09-01" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("2026")
    end
  end
end
```

- [ ] **Step 3: Run both to confirm they fail**

```bash
docker compose run --rm web bin/rspec spec/helpers/days_helper_spec.rb spec/requests/days_spec.rb
```

Expected: FAIL — `DaysHelper` is missing and the view is a placeholder.

- [ ] **Step 4: Write the helper**

Create `app/helpers/days_helper.rb`:

```ruby
module DaysHelper
  # SVG rings are drawn with stroke-dasharray: the first number is the visible
  # arc, the second the full circumference. The arc caps at full even when the
  # goal is exceeded — the overage is shown in the numbers, not the ring.
  def ring_dash_array(current, goal, circumference)
    fraction = goal.to_f.positive? ? (current.to_f / goal.to_f).clamp(0, 1) : 0
    "#{(fraction * circumference).round(1)} #{circumference}"
  end
end
```

- [ ] **Step 5: Write the ring partial**

Create `app/views/days/_ring.html.erb`:

```erb
<%# locals: label, current, goal, unit, color_var %>
<div class="ring">
  <svg viewBox="0 0 120 120" role="img" aria-label="<%= label %>">
    <circle class="ring__track" cx="60" cy="60" r="52" />
    <circle class="ring__value" cx="60" cy="60" r="52"
            style="stroke: var(<%= color_var %>);"
            stroke-dasharray="<%= ring_dash_array(current, goal, 326.7) %>" />
  </svg>
  <div class="ring__label">
    <strong><%= number_with_precision(current, precision: 0) %></strong>
    <span class="muted">/ <%= number_with_precision(goal, precision: 0) %><%= unit %></span>
    <div class="muted"><%= label %></div>
  </div>
</div>
```

- [ ] **Step 6: Write the meal partial**

Create `app/views/days/_meal.html.erb`:

```erb
<%# locals: meal, entries %>
<section class="stack">
  <div class="row" style="justify-content: space-between;">
    <h2><%= t("meals.#{meal}") %></h2>
    <%= link_to "Agregar", new_entry_path(meal: meal), class: "button" %>
  </div>

  <% if entries.empty? %>
    <p class="muted">Nada registrado.</p>
  <% else %>
    <%= render partial: "entries/entry", collection: entries %>
  <% end %>
</section>
```

- [ ] **Step 7: Replace the day view**

Replace `app/views/days/show.html.erb`:

```erb
<% content_for :title, "Hoy" %>

<div class="row" style="justify-content: space-between;">
  <%= link_to "‹", root_path(date: @day_log.date - 1.day), class: "button" %>
  <h1><%= l @day_log.date, format: :long %></h1>
  <%= link_to "›", root_path(date: @day_log.date + 1.day), class: "button" %>
</div>

<div class="rings">
  <%= render "ring", label: "kcal", current: @day_log.totals[:kcal],
        goal: @day_log.goal.kcal, unit: "", color_var: "--color-accent" %>
  <%= render "ring", label: "Proteína", current: @day_log.totals[:protein_g],
        goal: @day_log.goal.protein_g, unit: "g", color_var: "--color-protein" %>
  <%= render "ring", label: "Carbos", current: @day_log.totals[:carbs_g],
        goal: @day_log.goal.carbs_g, unit: "g", color_var: "--color-carbs" %>
  <%= render "ring", label: "Grasa", current: @day_log.totals[:fat_g],
        goal: @day_log.goal.fat_g, unit: "g", color_var: "--color-fat" %>
</div>

<div class="card remaining">
  <span class="remaining__value <%= "negative" if @day_log.remaining[:kcal].negative? %>">
    <%= number_with_precision(@day_log.remaining[:kcal], precision: 0) %>
  </span>
  <span class="muted">kcal restantes</span>
</div>

<% Entry::MEALS.each do |meal| %>
  <%= render "meal", meal: meal, entries: @day_log.entries_for(meal) %>
<% end %>
```

- [ ] **Step 8: Style the rings**

Append to `app/assets/stylesheets/_components.scss`:

```scss
.rings {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: var(--space-3);
}

@media (min-width: 40rem) {
  .rings {
    grid-template-columns: repeat(4, 1fr);
  }
}

.ring {
  position: relative;

  svg {
    display: block;
    width: 100%;
    height: auto;
    transform: rotate(-90deg);
  }

  &__track,
  &__value {
    fill: none;
    stroke-width: 8;
    stroke-linecap: round;
  }

  &__track {
    stroke: var(--color-border);
  }

  &__label {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    font-size: 0.8125rem;
    text-align: center;
  }
}

.remaining {
  text-align: center;

  &__value {
    display: block;
    font-size: 2rem;
    font-weight: 700;
  }
}
```

- [ ] **Step 9: Run the tests**

```bash
docker compose run --rm web bin/rspec spec/helpers/days_helper_spec.rb spec/requests/days_spec.rb
```

Expected: PASS, 9 examples.

- [ ] **Step 10: Run the whole suite, lint, and look at it**

```bash
docker compose run --rm web bin/rspec
docker compose run --rm web bin/rubocop
docker compose up -d
```

Open `http://localhost:3000` at a 375 px viewport width. Confirm: the four rings sit two-by-two, nothing scrolls horizontally, and every button clears 44 px of height.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "Add the day dashboard with macro progress rings"
```

---

## Done when

- `docker compose run --rm web bin/rspec` is green.
- `docker compose run --rm web bin/rubocop` reports no offenses.
- A signed-in user can create a food with a serving, set a goal, log several items into a meal without renavigating, and see the day's rings and remaining calories.
- The page does not scroll horizontally at 375 px.
