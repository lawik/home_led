defmodule HomeLed.Effects.Breathe do
  @moduledoc "The chosen colour, swelling and fading over four seconds, never quite out."
  @behaviour HomeLed.Effect

  @period_ms 4_000
  @floor 0.12

  @impl true
  def name, do: "Breathe"

  @impl true
  def fps, do: 30

  @impl true
  def init(_ctx), do: nil

  @impl true
  def frame(state, %{count: count, color: color, time_ms: t}) do
    phase = 0.5 - 0.5 * :math.cos(2 * :math.pi() * rem(t, @period_ms) / @period_ms)
    level = @floor + (1 - @floor) * phase
    {r, g, b} = HomeLed.Color.scale(color, round(level * 255))
    {:binary.copy(<<r, g, b>>, count), state}
  end
end
