class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges,
  # import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_authentication

  private
    def current_user
      @current_user ||= User.find_by(id: session[:user_id])
    end
    helper_method :current_user

    def require_authentication
      redirect_to sign_in_path unless current_user
    end

    # params.require(:key) only raises ParameterMissing when the value is
    # blank; a scalar value ("food=boom") is present, so #require happily
    # returns the bare String and the caller's #permit blows up with a
    # NoMethodError instead. Every *_params method in this app builds its
    # permitted hash from a nested param, so require that shape explicitly.
    def require_params_hash(key)
      value = params[key]
      raise ActionController::ParameterMissing, key unless value.is_a?(ActionController::Parameters)

      value
    end
end
