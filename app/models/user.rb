class User < ApplicationRecord
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
    user.email = email.strip.downcase
    user.name = auth.info.name
    user.avatar_url = auth.info.image
    return nil unless user.save

    user
  end
end
