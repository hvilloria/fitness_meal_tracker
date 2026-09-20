# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Starter catalog: three real cuts of chicken and beef, one per user.
#
# Figures are USDA values for the COOKED cut, per 100 g. Cooked and raw
# differ by roughly 30% because cooking drives off water — do not paste a
# raw-cut value in here without converting it first.
STARTER_FOODS = [
  { name: "Pechuga de pollo", state: "cooked", kcal_per_100: 165, protein_per_100: 31.0, carbs_per_100: 0, fat_per_100: 3.6 },
  { name: "Muslo de pollo", state: "cooked", kcal_per_100: 209, protein_per_100: 25.9, carbs_per_100: 0, fat_per_100: 10.9 },
  { name: "Bola de lomo", state: "cooked", kcal_per_100: 163, protein_per_100: 29.9, carbs_per_100: 0, fat_per_100: 3.9 }
].freeze

User.find_each do |user|
  STARTER_FOODS.each do |attributes|
    user.foods.find_or_create_by!(name: attributes[:name]) do |food|
      food.assign_attributes(attributes)
    end
  end
end
