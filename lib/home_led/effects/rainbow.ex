defmodule HomeLed.Effects.Rainbow do
  @moduledoc """
  The whole hue wheel laid along the strip and slowly turning, at the chosen brightness.
  Ignores the chosen colour. One pixel cycles through every hue instead.
  """
  @behaviour HomeLed.Effect

  @cycle_ms 8_000

  @impl true
  def name, do: "Rainbow"

  @impl true
  def fps, do: 30

  @impl true
  def init(_ctx), do: nil

  @impl true
  def frame(state, %{count: count, brightness: brightness, time_ms: t}) do
    offset = div(rem(t, @cycle_ms) * 256, @cycle_ms)
    value = round(brightness * 255)

    frame =
      for i <- 0..(count - 1), into: <<>> do
        hue = rem(offset + div(i * 256, count), 256)
        {r, g, b} = HomeLed.Color.hsv_to_rgb(hue, 255, value)
        <<r, g, b>>
      end

    {frame, state}
  end
end
