class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges,
  # import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :require_authentication

  private
    def current_user
      @current_user ||= User.find_by(id: session[:user_id])
    end
    helper_method :current_user

    def require_authentication
      redirect_to sign_in_path unless current_user
    end
end
