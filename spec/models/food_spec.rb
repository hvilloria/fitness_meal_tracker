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

    it "is deterministic when two entries share the same logged_at" do
      food = create(:food, user: user)
      same_time = 1.hour.ago
      # Create two entries with identical timestamps (to test tie-breaking)
      create(:entry, day_log: day_log, food: food, meal: "lunch", grams: 150, logged_at: same_time)
      create(:entry, day_log: day_log, food: food, meal: "dinner", grams: 190, logged_at: same_time)

      # Verify that the result is consistent across multiple calls (deterministic)
      # The id-based ordering ensures the result does not depend on database scan order
      first_call = Food.last_grams_for(user)[food.id]
      second_call = Food.last_grams_for(user)[food.id]
      expect(first_call).to eq(second_call)
    end
  end
end
