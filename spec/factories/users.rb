FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    name { "Hosward" }
    provider { "google_oauth2" }
    sequence(:uid) { |n| "uid-#{n}" }
    day_cutoff_hour { 4 }
  end
end
