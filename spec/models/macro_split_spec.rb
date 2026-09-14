require "rails_helper"

RSpec.describe MacroSplit, type: :model do
  describe ".kcal_from" do
    it "applies 4/4/9" do
      expect(MacroSplit.kcal_from(protein_g: 180, carbs_g: 220, fat_g: 78)).to eq(2302)
    end

    it "is zero for an empty split" do
      expect(MacroSplit.kcal_from(protein_g: 0, carbs_g: 0, fat_g: 0)).to eq(0)
    end

    it "treats nil as zero" do
      expect(MacroSplit.kcal_from(protein_g: 100, carbs_g: nil, fat_g: nil)).to eq(400)
    end
  end

  describe ".percentages" do
    it "reports each macro's share of the total" do
      result = MacroSplit.percentages(protein_g: 180, carbs_g: 220, fat_g: 78)

      expect(result[:protein]).to be_within(0.1).of(31.3)
      expect(result[:carbs]).to be_within(0.1).of(38.2)
      expect(result[:fat]).to be_within(0.1).of(30.5)
    end

    it "returns zeros rather than dividing by zero" do
      expect(MacroSplit.percentages(protein_g: 0, carbs_g: 0, fat_g: 0))
        .to eq(protein: 0.0, carbs: 0.0, fat: 0.0)
    end
  end

  describe ".from_kcal" do
    it "seeds a new goal at 25/50/25" do
      expect(MacroSplit.from_kcal(2500)).to eq(protein_g: 156, carbs_g: 313, fat_g: 69)
    end

    it "produces a split that reconstructs approximately the same total" do
      split = MacroSplit.from_kcal(2500)

      expect(MacroSplit.kcal_from(**split)).to be_within(10).of(2500)
    end

    it "is all zeros for a non-positive target" do
      expect(MacroSplit.from_kcal(0)).to eq(protein_g: 0, carbs_g: 0, fat_g: 0)
    end
  end
end
