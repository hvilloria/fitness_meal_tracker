class DaysController < ApplicationController
  rescue_from DayLog::MissingGoal, with: :redirect_to_goal

  def show
    @day_log = DayLog.for(current_user, requested_time)
  end

  private
    def requested_time
      return Time.current if params[:date].blank?

      Date.parse(params[:date]).in_time_zone(Time.zone).change(hour: 12)
    rescue Date::Error
      Time.current
    end

    def redirect_to_goal
      redirect_to edit_goal_path, notice: "Primero definí tu meta."
    end
end
