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
