defmodule HomeLed.Entities.StripEffect do
  @moduledoc """
  The strip's effect in Home Assistant, as a select next to the light: "Solid",
  "Flicker", "Breathe", "Rainbow" (`HomeLed.Effects`). Picking one sets it on
  `HomeLed.Scene`; the light's colour and brightness still apply.

  Home Assistant's MQTT light has an effect list of its own, which would put this in the
  light card instead; Homex's light entity does not carry it yet.
  """
  use Homex.Entity.Select,
    id: :strip_effect,
    name: "LED strip effect",
    options: HomeLed.Effects.names()

  alias HomeLed.{Effects, Scene}

  def handle_init(entity) do
    :ok = Scene.subscribe(scene(entity))
    follow(entity, Scene.get(scene(entity)))
  end

  def handle_info({:scene, scene}, entity), do: follow(entity, scene)
  def handle_info(_msg, entity), do: entity

  defp follow(entity, %{effect: effect}), do: set_option(entity, Effects.name(effect))

  def handle_option(entity, option) do
    case Effects.from_name(option) do
      {:ok, effect} -> Scene.set_effect(scene(entity), effect)
      :error -> :ok
    end

    entity
  end

  defp scene(entity), do: get_private(entity, :scene) || Scene
end
