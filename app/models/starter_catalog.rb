# The three starter foods, so a brand-new user's entry form isn't empty on
# day one. Seeded once, from User.from_omniauth, when the user row is first
# created — never on every sign-in, and never on server boot (see
# bin/docker-entrypoint's history).
#
# The catalog is shared across users (see FoodsController#index), so
# idempotency here is catalog-wide rather than per user: a starter food is
# created only when no food anywhere already has that name, archived ones
# included. That is
# what keeps a second user's first sign-in from duplicating the first
# user's copy, and what keeps a repeat run of db/seeds.rb from piling up
# duplicates in development.
#
# db/seeds.rb calls the same #seed_for so development seeding stays in sync
# with this list instead of duplicating the figures.
class StarterCatalog
  # Figures are USDA values for the COOKED cut, per 100 g. Cooked and raw
  # differ by roughly 30% because cooking drives off water — do not paste a
  # raw-cut value in here without converting it first.
  FOODS = [
    { name: "Pechuga de pollo", state: "cooked", kcal_per_100: 165, protein_per_100: 31.0, carbs_per_100: 0, fat_per_100: 3.6 },
    { name: "Muslo de pollo", state: "cooked", kcal_per_100: 209, protein_per_100: 25.9, carbs_per_100: 0, fat_per_100: 10.9 },
    { name: "Bola de lomo", state: "cooked", kcal_per_100: 163, protein_per_100: 29.9, carbs_per_100: 0, fat_per_100: 3.9 }
  ].freeze

  class << self
    # Checked catalog-wide rather than per user, and against every food
    # rather than only the active ones. Archived counts: a starter food
    # someone deliberately archived must stay gone, including for a user
    # who signs in later — otherwise the next sign-in quietly resurrects
    # a copy of something the household already decided it did not want.
    def seed_for(user)
      FOODS.each do |attributes|
        next if Food.exists?(name: attributes[:name])

        user.foods.create!(attributes)
      end
    end
  end
end
