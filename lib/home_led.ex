defmodule HomeLed do
  @moduledoc """
  Nerves firmware that turns a WS281x LED strip (and optionally a plain GPIO LED) into

    * a Home Assistant light with an effect select, through Homex and MQTT discovery
      (`HomeLed.Entities`), and
    * a `:light` capability on the home cluster, through home_base (`Home.Light`).

  `HomeLed.Scene` decides what the strip shows and `HomeLed.Strip` drives it; how many
  pixels it has and their channel order are persisted settings (`HomeLed.Settings`).
  These functions are the IEx-friendly front door.
  """

  alias HomeLed.{Effects, Scene, Settings, Strip}

  @doc "How many pixels the strip is driven with."
  @spec led_count() :: pos_integer()
  defdelegate led_count(), to: Settings

  @doc """
  Set how many pixels the strip has. Persisted, so it survives reboots and firmware
  updates; the strip repaints at the new length straight away.
  """
  @spec set_led_count(pos_integer()) :: :ok
  defdelegate set_led_count(count), to: Settings

  @doc "The strip's channel order, `:grb` for WS2812."
  @spec color_order() :: HomeLed.Color.order()
  defdelegate color_order(), to: Settings

  @doc """
  Set the strip's channel order: `:grb` for WS2812, `:grbw` for SK6812 RGBW, or any other
  of `HomeLed.Color.orders/0`. Persisted; the strip repaints in the new order straight away.
  """
  @spec set_color_order(HomeLed.Color.order()) :: :ok
  defdelegate set_color_order(order), to: Settings

  @doc "What the strip shows: `%{on, color, brightness, effect}` (see `HomeLed.Scene`)."
  @spec scene() :: Scene.t()
  defdelegate scene(), to: Scene, as: :get

  @doc "Turn the light on or off, as Home Assistant would."
  @spec set_on(boolean()) :: :ok
  def set_on(on?), do: Scene.set_on(Scene, on?)

  @doc "The light's hue, components `0.0..1.0`; brightness is separate."
  @spec set_color(Scene.hue()) :: :ok
  def set_color(hue), do: Scene.set_color(Scene, hue)

  @doc "The light's brightness, `0.0..1.0`."
  @spec set_brightness(number()) :: :ok
  def set_brightness(brightness), do: Scene.set_brightness(Scene, brightness)

  @doc "The effect, `:solid` or one of `effects/0`."
  @spec set_effect(Effects.effect()) :: :ok | {:error, :unknown_effect}
  def set_effect(effect), do: Scene.set_effect(Scene, effect)

  @doc "The effects, as `{name, effect}`."
  @spec effects() :: [{String.t(), Effects.effect()}]
  defdelegate effects(), to: Effects, as: :all

  @doc """
  Paint the strip pixel by pixel from RGB bytes, three per pixel, behind the scene's
  back. A running effect paints over it on its next frame.
  """
  @spec set_frame(binary()) :: :ok
  def set_frame(frame), do: Strip.set_frame(Strip, frame)
end
