require "rails_helper"

RSpec.describe Goal, type: :model do
  subject(:goal) { build(:goal) }

  it { is_expected.to belong_to(:user) }

  it "rejects negative macros" do
    expect(build(:goal, protein_g: -1)).not_to be_valid
  end

  describe "integer(4-byte) overflow" do
    it "rejects a macro at or above the column's bound" do
      expect(build(:goal, protein_g: 100_000)).not_to be_valid
    end

    it "rejects a macro that is itself in range for the column but whose derived kcal is not, instead of raising on save" do
      goal = build(:goal, protein_g: 2_000_000_000, carbs_g: 0, fat_g: 0)

      expect { goal.save }.not_to raise_error
      expect(goal).not_to be_persisted
      expect(goal.errors.attribute_names).to include(:protein_g)
    end
  end

  describe "kcal" do
    it "is always derived from the macros on save" do
      goal = create(:goal, protein_g: 180, carbs_g: 220, fat_g: 78, kcal: 9999)

      expect(goal.kcal).to eq(2302)
    end

    it "follows a macro change" do
      goal = create(:goal, protein_g: 144, carbs_g: 325, fat_g: 69)
      expect(goal.kcal).to eq(2497)

      goal.update!(protein_g: 180)

      expect(goal.kcal).to eq(2641)
    end
  end

  describe "#percentages" do
    it "delegates to MacroSplit" do
      goal = build(:goal, protein_g: 180, carbs_g: 220, fat_g: 78)

      expect(goal.percentages[:protein]).to be_within(0.1).of(31.3)
    end
  end

  describe "the default goal" do
    let(:user) { create(:user) }

    it "clears the previous default when another is set" do
      first = create(:goal, user: user, is_default: true)
      second = create(:goal, user: user, is_default: true)

      expect(first.reload.is_default).to be(false)
      expect(second.reload.is_default).to be(true)
    end

    it "is exposed through User#default_goal" do
      create(:goal, user: user, is_default: false)
      chosen = create(:goal, user: user, is_default: true)

      expect(user.reload.default_goal).to eq(chosen)
    end

    it "leaves other users alone" do
      other = create(:goal, is_default: true)
      create(:goal, user: user, is_default: true)

      expect(other.reload.is_default).to be(true)
    end

    it "allows each user to have their own default goal independently" do
      other_user = create(:user)
      user_default = create(:goal, user: user, is_default: true)
      other_default = create(:goal, user: other_user, is_default: true)

      expect(user.reload.default_goal).to eq(user_default)
      expect(other_user.reload.default_goal).to eq(other_default)
    end

    it "is rejected by the database when the callback is bypassed via update_column" do
      first = create(:goal, user: user, is_default: true)
      second = create(:goal, user: user, is_default: false)

      expect {
        second.update_column(:is_default, true)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
