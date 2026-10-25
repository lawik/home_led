defmodule HomeLed.Entities.SettingsEntitiesTest do
  @moduledoc "The LED count and colour order knobs against the application's Settings table."
  use ExUnit.Case

  alias HomeLed.Entities.{ColorOrder, LedCount}
  alias HomeLed.Settings

  setup do
    count = Settings.led_count()
    order = Settings.color_order()
    on_exit(fn -> Settings.set_led_count(count) && Settings.set_color_order(order) end)
    :ok
  end

  defp entity(module) do
    {:ok, entity} = module.new()
    values = Map.new(entity.descriptor.fields, fn {key, _} -> {key, nil} end)
    %{entity | values: values}
  end

  test "report the settings at init and write them on command" do
    Settings.set_led_count(7)
    Settings.set_color_order(:bgr)

    count = entity(LedCount) |> LedCount.setup()
    assert count.changes[:state] == 7
    order = entity(ColorOrder) |> ColorOrder.setup()
    assert order.changes[:state] == "BGR"

    assert order.descriptor.options.options ==
             ~w(RGB RBG GRB GBR BRG BGR RGBW RBGW GRBW GBRW BRGW BGRW)

    count = LedCount.handle_command(%{state: 12.0}, count)
    assert count.changes[:state] == 12
    assert Settings.led_count() == 12

    order = ColorOrder.handle_command(%{state: "RGB"}, order)
    assert order.changes[:state] == "RGB"
    assert Settings.color_order() == :rgb

    order = ColorOrder.handle_command(%{state: "XYZ"}, order)
    assert Settings.color_order() == :rgb
    assert order.changes[:state] == "RGB"
  end

  test "follow the settings when IEx changes them" do
    count = entity(LedCount) |> LedCount.setup()
    order = entity(ColorOrder) |> ColorOrder.setup()

    Settings.set_led_count(3)
    assert_receive %PropertyTable.Event{property: ["leds", "count"]} = count_event
    assert LedCount.handle_info(count_event, count).changes[:state] == 3

    Settings.set_color_order(:gbr)
    assert_receive %PropertyTable.Event{property: ["leds", "color_order"]} = order_event
    assert ColorOrder.handle_info(order_event, order).changes[:state] == "GBR"
  end
end
