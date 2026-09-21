# The three foods a brand-new user starts with, so the entry form isn't
# empty on day one. Seeded once, from User.from_omniauth, when the user row
# is first created — never on every sign-in, and never on server boot (see
# bin/docker-entrypoint's history): re-running this must not resurrect a
# food the user deliberately deleted or archived.
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
    # find_or_create_by! keeps this idempotent per user: a repeat call (from
    # db/seeds.rb, run more than once) creates nothing new, and it never
    # re-creates a food the user renamed away from, deleted or archived,
    # because it only ever looks for the starter name — an archived row is
    # still found by name and left alone rather than duplicated.
    def seed_for(user)
      FOODS.each do |attributes|
        user.foods.find_or_create_by!(name: attributes[:name]) do |food|
          food.assign_attributes(attributes)
        end
      end
    end
  end
end
