defmodule HomeLed.Entities.ColorOrder do
  @moduledoc """
  The strip's channel order (GRB for WS2812, RGB, ...) as a select in Home Assistant.
  Writes `HomeLed.Settings.set_color_order/1` (persisted) and follows the setting. Handy
  when a strip lights up in the wrong colours: pick orders until red is red.
  """
  use Homex.Entity.Select,
    id: :color_order,
    name: "LED color order",
    options: Enum.map(HomeLed.Settings.orders(), &HomeLed.Entities.ColorOrder.option/1)

  alias HomeLed.Settings

  @doc "The select option for an order: `:grb` is \"GRB\"."
  def option(order), do: order |> Atom.to_string() |> String.upcase()

  def handle_init(entity) do
    Settings.subscribe()
    set_option(entity, option(Settings.color_order()))
  end

  def handle_option(entity, option) do
    case Enum.find(Settings.orders(), &(option(&1) == option)) do
      # the select staged the unknown option already; put the real one back
      nil -> set_option(entity, option(Settings.color_order()))
      order -> Settings.set_color_order(order) && set_option(entity, option)
    end
  end

  def handle_info(%PropertyTable.Event{property: ["leds", "color_order"], value: order}, entity)
      when is_atom(order),
      do: set_option(entity, option(order))

  def handle_info(_msg, entity), do: entity
end
