class ProgressController < ApplicationController
  def show
    @summary = ProgressSummary.new(current_user)
  end
end
