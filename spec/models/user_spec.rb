require "rails_helper"

RSpec.describe User, type: :model do
  def auth_hash(email:, uid: "123", name: "Hosward", image: "http://example.com/a.jpg")
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { email: email, name: name, image: image }
    )
  end

  describe ".allowed?" do
    it "accepts an email listed in ALLOWED_EMAILS" do
      allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com,b@example.com")
      expect(User.allowed?("b@example.com")).to be(true)
    end

    it "rejects an email that is not listed" do
      allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
      expect(User.allowed?("intruder@example.com")).to be(false)
    end

    it "ignores surrounding whitespace and case" do
      allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return(" A@Example.com , b@example.com ")
      expect(User.allowed?("a@example.com")).to be(true)
    end

    it "rejects everything when ALLOWED_EMAILS is unset" do
      allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return(nil)
      expect(User.allowed?("a@example.com")).to be(false)
    end
  end

  describe ".from_omniauth" do
    before do
      allow(ENV).to receive(:[]).with("ALLOWED_EMAILS").and_return("a@example.com")
    end

    it "creates a user for an allowed email" do
      expect { User.from_omniauth(auth_hash(email: "a@example.com")) }
        .to change(User, :count).by(1)
    end

    it "returns nil and creates nothing for a disallowed email" do
      expect { expect(User.from_omniauth(auth_hash(email: "no@example.com"))).to be_nil }
        .not_to change(User, :count)
    end

    it "reuses the existing user and refreshes the profile" do
      User.from_omniauth(auth_hash(email: "a@example.com", name: "Old"))

      expect { User.from_omniauth(auth_hash(email: "a@example.com", name: "New")) }
        .not_to change(User, :count)
      expect(User.last.name).to eq("New")
    end

    it "defaults the day cutoff to 4" do
      user = User.from_omniauth(auth_hash(email: "a@example.com"))
      expect(user.day_cutoff_hour).to eq(4)
    end
  end
end
