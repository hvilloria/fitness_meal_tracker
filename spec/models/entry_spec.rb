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
      # Rails 8.1's enum (with validate: true) no longer raises ArgumentError
      # on assignment of an out-of-range value; it stores it and fails
      # validation instead. Verified against the installed Rails version.
      entry = build(:entry, day_log: day_log, food: food, meal: "extra")

      expect(entry).not_to be_valid
      expect(entry.errors.attribute_names).to include(:meal)
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

      # Not `day_log.reload`: reload clears the cached `goal` association,
      # which would silently drop the stub above and fetch a fresh Goal.
      expect(day_log.remaining[:kcal]).to be_negative
    end
  end
end
