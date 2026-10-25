defmodule HomeLed.Entities.DisabledLeds do
  @moduledoc """
  Which LEDs the strip leaves dark, as a text field in Home Assistant: `"5"`, `"3-8"`
  or `"3-8, 10-200"` (see `HomeLed.LedRanges`). Writes
  `HomeLed.Settings.set_disabled_ranges/1` (persisted) and follows the setting. Text
  that does not parse, or has overlapping ranges, is logged and the field snaps back
  to the current setting.
  """
  use Homex.Entity.Text,
    id: :disabled_leds,
    name: "Disabled LEDs",
    min: 0,
    max: 255,
    pattern: "^[0-9,; -]*$"

  require Logger
  alias HomeLed.{LedRanges, Settings}

  def handle_init(entity) do
    Settings.subscribe()
    set_text(entity, current())
  end

  def handle_text(entity, text) when is_binary(text) do
    case LedRanges.parse(text) do
      {:ok, ranges} ->
        Settings.set_disabled_ranges(ranges)
        set_text(entity, LedRanges.format(ranges))

      {:error, reason} ->
        Logger.warning("ignoring disabled LEDs #{inspect(text)}: #{reason}")
        # the text entity staged the bad text already; put the real one back
        set_text(entity, current())
    end
  end

  def handle_info(%PropertyTable.Event{property: ["leds", "disabled"], value: ranges}, entity)
      when is_list(ranges),
      do: set_text(entity, LedRanges.format(ranges))

  def handle_info(_msg, entity), do: entity

  defp current, do: LedRanges.format(Settings.disabled_ranges())
end
