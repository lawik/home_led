defmodule HomeLed.Color do
  @moduledoc """
  The little colour arithmetic between Home Assistant and the strip.

  Colours are `{r, g, b}` tuples of bytes. Homex hands over a *hue* with its brightest
  component at 1.0 and a separate brightness in `0.0..1.0`; `emitted/3` turns the two
  into the bytes the LEDs should show.
  """

  import Bitwise

  @type rgb :: {byte(), byte(), byte()}
  @type order :: :rgb | :rbg | :grb | :gbr | :brg | :bgr

  @third div(256, 3)
  @two_thirds div(512, 3)

  @doc """
  The bytes to emit for a Homex hue (components `0.0..1.0`) at a brightness
  (`0.0..1.0`). Off when `on?` is false.

      iex> HomeLed.Color.emitted({1.0, 0.5, 0.0}, 0.5, true)
      {128, 64, 0}
      iex> HomeLed.Color.emitted({1.0, 1.0, 1.0}, 1.0, false)
      {0, 0, 0}
  """
  @spec emitted({number(), number(), number()}, number(), boolean()) :: rgb()
  def emitted(_hue, _brightness, false), do: {0, 0, 0}

  def emitted({r, g, b}, brightness, true) do
    {to_byte(r * brightness), to_byte(g * brightness), to_byte(b * brightness)}
  end

  @doc """
  Hue, saturation and value bytes to RGB. A hue of 0 is red, 85 green, 170 blue; the
  wheel is the eight-section "rainbow" from FastLED and Fledex, which widens yellow since
  yellow LEDs read dimmer than the arithmetic says.
  """
  @spec hsv_to_rgb(byte(), byte(), byte()) :: rgb()
  def hsv_to_rgb(h, s, v) when h in 0..255 and s in 0..255 and v in 0..255 do
    h |> hue_rgb() |> desaturate(s) |> scale(v)
  end

  @doc "Dims a colour: 255 leaves it alone, 0 is black."
  @spec scale(rgb(), byte()) :: rgb()
  def scale({r, g, b}, level) when level in 0..255 do
    {div(r * level, 255), div(g * level, 255), div(b * level, 255)}
  end

  @doc """
  Packs one pixel into the three bytes its strip expects. Which channel goes first
  differs per chip: a WS2812 pixel takes `:grb`.
  """
  @spec pack(rgb(), order()) :: <<_::24>>
  def pack({r, g, b}, :rgb), do: <<r, g, b>>
  def pack({r, g, b}, :rbg), do: <<r, b, g>>
  def pack({r, g, b}, :grb), do: <<g, r, b>>
  def pack({r, g, b}, :gbr), do: <<g, b, r>>
  def pack({r, g, b}, :brg), do: <<b, r, g>>
  def pack({r, g, b}, :bgr), do: <<b, g, r>>

  @doc "Reorders a whole RGB frame (three bytes per pixel) into the strip's channel order."
  @spec pack_frame(binary(), order()) :: binary()
  def pack_frame(frame, :rgb), do: frame

  def pack_frame(frame, order) do
    for <<r, g, b <- frame>>, into: <<>>, do: pack({r, g, b}, order)
  end

  defp to_byte(value), do: value |> Kernel.*(255) |> round() |> max(0) |> min(255)

  # the hue byte splits into eight sections of 32, each a straight run between two of
  # red, orange, yellow, green, aqua, blue, purple and pink
  defp hue_rgb(h) do
    offset8 = (h &&& 0x1F) <<< 3
    third = (offset8 * @third) >>> 8
    two_thirds = (offset8 * @two_thirds) >>> 8

    case h >>> 5 do
      0 -> {255 - third, third, 0}
      1 -> {171, 85 + third, 0}
      2 -> {171 - two_thirds, 170 + third, 0}
      3 -> {0, 255 - third, third}
      4 -> {0, 171 - two_thirds, 85 + two_thirds}
      5 -> {third, 0, 255 - third}
      6 -> {85 + third, 0, 171 - third}
      7 -> {170 + third, 0, 85 - third}
    end
  end

  # saturation pulls the colour towards white: 255 leaves it pure, 0 is white
  defp desaturate(rgb, 255), do: rgb

  defp desaturate({r, g, b}, s) do
    white = 255 - s

    {r + div((255 - r) * white, 255), g + div((255 - g) * white, 255),
     b + div((255 - b) * white, 255)}
  end
end
