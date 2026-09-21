FactoryBot.define do
  factory :food do
    user
    name { "Port Salut light" }
    brand { "La Serenísima" }
    state { nil }
    kcal_per_100 { 220 }
    protein_per_100 { 27 }
    carbs_per_100 { 0 }
    fat_per_100 { 12 }
    unit { "grams" }

    trait :milliliters do
      name { "Coca-Cola" }
      brand { nil }
      kcal_per_100 { 42 }
      protein_per_100 { 0 }
      carbs_per_100 { 10.6 }
      fat_per_100 { 0 }
      unit { "milliliters" }
    end
  end
end
