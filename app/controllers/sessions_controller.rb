class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: %i[new create failure passthru]

  def new
    redirect_to root_path if current_user
  end

  def passthru
    head :not_found
  end

  def create
    auth = request.env["omniauth.auth"]
    user = auth && User.from_omniauth(auth)

    if user
      reset_session
      session[:user_id] = user.id
      redirect_to root_path
    else
      redirect_to sign_in_path, alert: "Esa cuenta no tiene acceso a esta aplicación."
    end
  end

  def failure
    redirect_to sign_in_path, alert: "No se pudo completar el inicio de sesión."
  end

  def destroy
    reset_session
    redirect_to sign_in_path
  end
end
