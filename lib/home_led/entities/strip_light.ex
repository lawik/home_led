defmodule HomeLed.Entities.StripLight do
  @moduledoc """
  The strip in Home Assistant: one RGB light (`Homex.Entity.Light`, mode `:rgb`).

  Home Assistant sets on/off, a hue and a brightness; they go to `HomeLed.Scene`, which
  paints the strip, solid or through the selected effect
  (`HomeLed.Entities.StripEffect`). The entity follows the scene (`HomeLed.Scene.subscribe/1`),
  so what the restored scene shows at boot, or what IEx sets, is what Home Assistant sees.

  Homex stages every field a command carries and then calls one hook per field, so each
  hook reads the staged values rather than its own argument alone.
  """
  use Homex.Entity.Light, id: :strip, name: "LED strip", modes: [:rgb]

  alias HomeLed.Scene

  def handle_init(entity) do
    :ok = Scene.subscribe(scene(entity))
    follow(entity, Scene.get(scene(entity)))
  end

  def handle_info({:scene, scene}, entity), do: follow(entity, scene)
  def handle_info(_msg, entity), do: entity

  defp follow(entity, %{on: on?, color: {r, g, b}, brightness: brightness}) do
    entity
    |> set_color({:rgb, r, g, b})
    |> set_brightness(brightness)
    |> then(&if(on?, do: set_on(&1), else: set_off(&1)))
  end

  def handle_on(entity), do: apply_state(entity, :on)
  def handle_off(entity), do: apply_state(entity, :on)
  def handle_brightness(entity, _brightness), do: apply_state(entity, :brightness)
  def handle_color(entity, _color), do: apply_state(entity, :color)

  defp apply_state(entity, field) do
    values = Map.merge(entity.values, entity.changes)
    scene = scene(entity)

    case field do
      :on -> Scene.set_on(scene, values[:state] == true)
      :brightness -> Scene.set_brightness(scene, values[:brightness] || 0.0)
      :color -> Scene.set_color(scene, hue(values[:color]))
    end

    entity
  end

  defp hue({:rgb, r, g, b}), do: {r, g, b}
  defp hue(nil), do: {1.0, 1.0, 1.0}

  defp scene(entity), do: get_private(entity, :scene) || Scene
end
