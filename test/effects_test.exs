defmodule HomeLed.EffectsTest do
  use ExUnit.Case, async: true

  alias HomeLed.Effects

  @ctx %{count: 5, color: {255, 80, 0}, brightness: 1.0, time_ms: 0}

  test "the list and names round-trip" do
    assert Effects.names() == ["Solid", "Flicker", "Breathe", "Rainbow"]
    for {name, effect} <- Effects.all(), do: assert(Effects.from_name(name) == {:ok, effect})
    assert Effects.from_name("Disco") == :error
    assert Effects.valid?(:solid) and Effects.valid?(Effects.Flicker)
    refute Effects.valid?(:disco)
  end

  test "flicker frames fit the strip and stay within the chosen colour" do
    state = Effects.Flicker.init(@ctx)

    {state, frames} =
      Enum.map_reduce(1..200, state, fn _, state ->
        {frame, state} = Effects.Flicker.frame(state, @ctx)
        {frame, state}
      end)
      |> then(fn {frames, state} -> {state, frames} end)

    assert length(state) == 5
    assert Enum.all?(frames, &(byte_size(&1) == 15))
    for frame <- frames, <<r, g, b <- frame>>, do: assert(r <= 255 and g <= 80 and b == 0)
    # it moves
    assert frames |> Enum.uniq() |> length() > 10
    # a strip that grew gets a fresh state
    {frame, state} = Effects.Flicker.frame(state, %{@ctx | count: 8})
    assert byte_size(frame) == 24 and length(state) == 8
  end

  test "breathe swells and fades the chosen colour" do
    {dark, _} = Effects.Breathe.frame(nil, @ctx)
    {bright, _} = Effects.Breathe.frame(nil, %{@ctx | time_ms: 2_000})
    assert <<r1, _, _>> <> _ = dark
    assert <<r2, _, _>> <> _ = bright
    assert r1 < r2 and r2 == 255
    assert byte_size(bright) == 15
  end

  test "rainbow spreads hues along the strip at the brightness" do
    {frame, _} = Effects.Rainbow.frame(nil, %{@ctx | brightness: 0.5})
    pixels = for <<r, g, b <- frame>>, do: {r, g, b}
    assert length(pixels) == 5 and length(Enum.uniq(pixels)) == 5
    assert Enum.all?(pixels, fn {r, g, b} -> max(r, max(g, b)) <= 128 end)
  end
end
