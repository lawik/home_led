defmodule HomeLed.Effects.Flicker do
  @moduledoc """
  A flame: every pixel flickers on its own around the chosen colour, as a candle in a
  pumpkin lantern does.

  Each pixel has a level that drifts towards a target; now and then the target jumps
  (a gust pulls it low once in a while), and a little noise rides on top. Lower levels
  dim green and blue more than red, so a flame in orange goes deep red as it dips rather
  than grey.
  """
  @behaviour HomeLed.Effect

  @impl true
  def name, do: "Flicker"

  @impl true
  def fps, do: 30

  @impl true
  def init(%{count: count}) do
    for _ <- 1..count, do: %{level: 0.7 + :rand.uniform() * 0.3, target: new_target()}
  end

  @impl true
  def frame(pixels, %{count: count} = ctx) when length(pixels) != count, do: frame(init(ctx), ctx)

  def frame(pixels, %{color: {r, g, b}}) do
    pixels = Enum.map(pixels, &step/1)

    frame =
      for %{level: level} <- pixels, into: <<>> do
        <<byte(r * level), byte(g * :math.pow(level, 1.6)), byte(b * :math.pow(level, 2.2))>>
      end

    {frame, pixels}
  end

  defp step(%{level: level, target: target}) do
    target =
      cond do
        :rand.uniform() < 0.012 -> 0.15 + :rand.uniform() * 0.2
        :rand.uniform() < 0.08 -> new_target()
        true -> target
      end

    noise = (:rand.uniform() - 0.5) * 0.08
    level = level + (target - level) * 0.25 + noise
    %{level: level |> max(0.05) |> min(1.0), target: target}
  end

  # the band a flame mostly lives in
  defp new_target, do: 0.45 + :rand.uniform() * 0.55

  defp byte(value), do: value |> round() |> max(0) |> min(255)
end
