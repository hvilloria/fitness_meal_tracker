require "rails_helper"

RSpec.describe StarterCatalog, type: :model do
  describe ".seed_for" do
    it "creates the three starter foods for a catalog that has none" do
      user = create(:user)

      expect { StarterCatalog.seed_for(user) }.to change(Food, :count).by(3)
    end

    it "creates nothing when the catalog already holds them" do
      StarterCatalog.seed_for(create(:user))

      expect { StarterCatalog.seed_for(create(:user)) }.not_to change(Food, :count)
    end

    # A starter food someone archived on purpose must stay gone. Checking only
    # Food.active would let the next user's first sign-in recreate a copy of
    # something the household already decided against.
    it "does not recreate a starter food that was archived" do
      StarterCatalog.seed_for(create(:user))
      Food.find_by(name: "Muslo de pollo").update!(archived_at: Time.current)

      expect { StarterCatalog.seed_for(create(:user)) }.not_to change(Food, :count)
      expect(Food.where(name: "Muslo de pollo").count).to eq(1)
    end
  end
end
