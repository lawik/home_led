defmodule HomeLed.Entities.GpioLight do
  @moduledoc """
  The GPIO LED in Home Assistant: an on/off light (`Homex.Entity.Light`, mode
  `:on_off`), the non-addressable sibling of `HomeLed.Entities.StripLight`. Only started
  when `config :home_led, gpio_led: pin` is set.
  """
  use Homex.Entity.Light, id: :gpio_led, name: "LED", modes: [:on_off]

  alias HomeLed.GpioLed

  def handle_init(entity), do: entity |> set_off() |> apply_state()
  def handle_on(entity), do: apply_state(entity)
  def handle_off(entity), do: apply_state(entity)

  defp apply_state(entity) do
    on? = Map.merge(entity.values, entity.changes)[:state] == true
    GpioLed.set(get_private(entity, :led) || GpioLed, on?)
    entity
  end
end
