defmodule HomeLed.ColorTest do
  use ExUnit.Case, async: true
  doctest HomeLed.Color

  alias HomeLed.Color

  test "emitted applies brightness to the hue and is black when off" do
    assert Color.emitted({1.0, 1.0, 1.0}, 1.0, true) == {255, 255, 255}
    assert Color.emitted({1.0, 0.0, 0.0}, 0.0, true) == {0, 0, 0}
    assert Color.emitted({0.2, 0.4, 1.0}, 0.5, true) == {26, 51, 128}
    assert Color.emitted({1.0, 1.0, 1.0}, 1.0, false) == {0, 0, 0}
  end

  test "four-channel orders split the white out of the colour" do
    assert Color.pack({255, 255, 255}, :grbw) == <<0, 0, 0, 255>>
    assert Color.pack({255, 77, 0}, :grbw) == <<77, 255, 0, 0>>
    assert Color.pack({200, 150, 100}, :rgbw) == <<100, 50, 0, 100>>
    assert Color.pack({200, 150, 100}, :bgrw) == <<0, 50, 100, 100>>
    assert Color.pack_frame(<<255, 255, 255, 255, 0, 0>>, :grbw) == <<0, 0, 0, 255, 0, 255, 0, 0>>
    assert Color.bytes_per_pixel(:grb) == 3 and Color.bytes_per_pixel(:grbw) == 4
    assert length(Color.orders()) == 12
  end

  test "pack puts the channels in the strip's order" do
    assert Color.pack({1, 2, 3}, :rgb) == <<1, 2, 3>>
    assert Color.pack({1, 2, 3}, :grb) == <<2, 1, 3>>
    assert Color.pack({1, 2, 3}, :bgr) == <<3, 2, 1>>
    assert Color.pack_frame(<<1, 2, 3, 4, 5, 6>>, :grb) == <<2, 1, 3, 5, 4, 6>>
    assert Color.pack_frame(<<1, 2, 3>>, :rgb) == <<1, 2, 3>>
  end

  test "scale dims" do
    assert Color.scale({255, 100, 0}, 255) == {255, 100, 0}
    assert Color.scale({255, 100, 0}, 0) == {0, 0, 0}
    assert Color.scale({255, 100, 0}, 128) == {128, 50, 0}
  end
end
