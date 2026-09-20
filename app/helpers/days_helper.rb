module DaysHelper
  # SVG rings are drawn with stroke-dasharray: the first number is the visible
  # arc, the second the full circumference. The arc caps at full even when the
  # goal is exceeded — the overage is shown in the numbers, not the ring.
  def ring_dash_array(current, goal, circumference)
    fraction = goal.to_f.positive? ? (current.to_f / goal.to_f).clamp(0.0, 1.0) : 0.0
    "#{(fraction * circumference).round(1)} #{circumference}"
  end

  # The same two guards as the ring, for the macro bars' CSS width: capped at
  # full when the goal is exceeded, and flat at zero for a zero goal rather
  # than dividing by it.
  def bar_percentage(current, goal)
    return 0.0 unless goal.to_f.positive?

    ((current.to_f / goal.to_f).clamp(0.0, 1.0) * 100).round(1)
  end
end
