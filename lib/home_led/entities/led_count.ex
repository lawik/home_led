defmodule HomeLed.Entities.LedCount do
  @moduledoc """
  How many LEDs the strip has, as a number in Home Assistant. Writes
  `HomeLed.Settings.set_led_count/1` (persisted) and follows the setting, so a change
  from IEx shows up in Home Assistant too.
  """
  use Homex.Entity.Number,
    id: :led_count,
    name: "LED count",
    min: 1,
    max: 1_000,
    step: 1,
    mode: :box

  alias HomeLed.Settings

  def handle_init(entity) do
    Settings.subscribe()
    set_number(entity, Settings.led_count())
  end

  def handle_number(entity, number) when is_number(number) do
    count = number |> round() |> max(1)
    Settings.set_led_count(count)
    set_number(entity, count)
  end

  def handle_info(%PropertyTable.Event{property: ["leds", "count"], value: count}, entity)
      when is_integer(count),
      do: set_number(entity, count)

  def handle_info(_msg, entity), do: entity
end
