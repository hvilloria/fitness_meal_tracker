# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Starter catalog: see StarterCatalog for the figures and the idempotency
# rationale. This only runs manually / in development now — production gets
# its starter catalog from User.from_omniauth, once per new user, not from
# this file (see bin/docker-entrypoint and User#seed_starter_catalog).
User.find_each { |user| StarterCatalog.seed_for(user) }
