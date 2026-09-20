require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module FitnessMealTracker
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.eager_load_paths << Rails.root.join("extras")

    config.time_zone = "America/Argentina/Buenos_Aires"
    config.i18n.default_locale = :es
    config.i18n.available_locales = [ :es, :en ]
    # Enable locale fallbacks for I18n (makes lookups for any locale fall
    # back to the default_locale when a translation cannot be found) in every
    # environment, not just production — otherwise validation error messages
    # render as "Translation missing" in development and test too.
    config.i18n.fallbacks = true

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Generate RSpec specs and FactoryBot factories instead of Minitest files.
    config.generators do |g|
      g.test_framework :rspec
      g.factory_bot dir: "spec/factories"
      g.orm :active_record, primary_key_type: :uuid
    end
  end
end
