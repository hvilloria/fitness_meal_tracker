class User < ApplicationRecord
  has_many :foods, dependent: :destroy
  has_many :goals, dependent: :destroy
  has_many :day_logs, dependent: :destroy

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true
  validates :provider, :uid, presence: true
  validates :day_cutoff_hour, inclusion: { in: 0..23 }

  # Google sign-in is open to anyone with a Google account, so membership is
  # decided here rather than by the provider.
  def self.allowed?(email)
    return false if email.blank?

    allowlist = ENV["ALLOWED_EMAILS"].to_s.split(",").map { |entry| entry.strip.downcase }
    allowlist.include?(email.strip.downcase)
  end

  def self.from_omniauth(auth)
    email = auth.info.email
    return nil unless allowed?(email)

    user = find_or_initialize_by(provider: auth.provider, uid: auth.uid)
    newly_created = user.new_record?
    user.email = email.strip.downcase
    user.name = auth.info.name
    user.avatar_url = auth.info.image
    return nil unless user.save

    # Only for a user just created: a returning user who deleted or archived
    # a starter food must never see it come back on a later sign-in.
    user.seed_starter_catalog if newly_created

    user
  end

  # Rescued rather than left to raise: a broken starter catalog (a bad
  # figure, a DB hiccup) must not lock a user out of an app they just
  # successfully authenticated into. Logged so the failure isn't silent.
  def seed_starter_catalog
    StarterCatalog.seed_for(self)
  rescue StandardError => e
    Rails.logger.error("Failed to seed starter catalog for user #{id}: #{e.message}")
  end

  def default_goal
    goals.find_by(is_default: true)
  end
end
