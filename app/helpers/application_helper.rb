module ApplicationHelper
  # Which tab of the bottom bar owns the screen being rendered. Keyed by
  # controller rather than by matching the path: /entries is reached from
  # the day screen and belongs under "Hoy", which no amount of string
  # matching on the URL would get right.
  NAV_SECTIONS = {
    "days" => :today,
    "entries" => :today,
    "foods" => :foods,
    "progress" => :progress,
    "goals" => :goal
  }.freeze

  def nav_section
    NAV_SECTIONS[controller.controller_name]
  end
end
