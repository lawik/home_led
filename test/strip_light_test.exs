defmodule HomeLed.Entities.StripLightTest do
  @moduledoc "The entities against a scene with a fake strip; Homex itself is not started."
  use ExUnit.Case, async: true

  alias HomeLed.{FakeStrip, Scene}
  alias HomeLed.Entities.{StripEffect, StripLight}

  setup do
    {:ok, strip} = FakeStrip.start_link()
    {:ok, scene} = Scene.start_link(strip: strip, persist: false, name: nil)
    {:ok, strip: strip, scene: scene}
  end

  # what Homex.Entity does in init/1 before setup/1, plus our scene for the test
  defp entity(module, scene) do
    {:ok, entity} = module.new()
    values = Map.new(entity.descriptor.fields, fn {key, _} -> {key, nil} end)
    %{entity | values: values} |> Homex.Entity.put_private(:scene, scene)
  end

  # what Homex.Entity.execute_change/1 does between commands
  defp commit(entity),
    do: %{entity | values: Map.merge(entity.values, entity.changes), changes: %{}}

  test "describes an rgb light and an effect select" do
    {:ok, light} = StripLight.new()
    assert light.descriptor.kind == :light
    assert light.descriptor.options.modes == [:rgb]
    {:ok, select} = StripEffect.new()
    assert select.descriptor.kind == :select
    assert select.descriptor.options.options == ["Solid", "Flicker", "Breathe", "Rainbow"]
  end

  test "reports the scene at init", %{scene: scene} do
    :ok = Scene.set_on(scene, true)
    :ok = Scene.set_color(scene, {1.0, 0.5, 0.0})
    :ok = Scene.set_brightness(scene, 0.4)
    :ok = Scene.set_effect(scene, HomeLed.Effects.Breathe)

    light = entity(StripLight, scene) |> StripLight.setup()
    assert light.changes[:state] == true
    assert light.changes[:color] == {:rgb, 1.0, 0.5, 0.0}
    assert light.changes[:brightness] == 0.4

    select = entity(StripEffect, scene) |> StripEffect.setup()
    assert select.changes[:state] == "Breathe"
  end

  test "follows the scene when it changes behind their back", %{scene: scene} do
    light = entity(StripLight, scene) |> StripLight.setup() |> commit()
    select = entity(StripEffect, scene) |> StripEffect.setup() |> commit()
    assert_receive {:scene, _initial}
    assert_receive {:scene, _initial_again}

    :ok = Scene.set_on(scene, true)
    :ok = Scene.set_effect(scene, HomeLed.Effects.Rainbow)
    assert_receive {:scene, _}
    assert_receive {:scene, latest}

    light = StripLight.handle_info({:scene, latest}, light)
    assert light.changes[:state] == true
    select = StripEffect.handle_info({:scene, latest}, select)
    assert select.changes[:state] == "Rainbow"
  end

  test "commands reach the scene and the strip", %{scene: scene, strip: strip} do
    light = entity(StripLight, scene) |> StripLight.setup() |> commit()

    light =
      StripLight.handle_command(
        %{state: true, brightness: 0.5, color: {:rgb, 1.0, 0.0, 0.0}},
        light
      )

    assert FakeStrip.shown(strip) == {:color, {128, 0, 0}}

    assert Map.take(Scene.get(scene), [:on, :color, :brightness]) ==
             %{on: true, color: {1.0, 0.0, 0.0}, brightness: 0.5}

    light = light |> commit() |> then(&StripLight.handle_command(%{brightness: 1.0}, &1))
    assert FakeStrip.shown(strip) == {:color, {255, 0, 0}}

    select = entity(StripEffect, scene) |> StripEffect.setup() |> commit()
    select = StripEffect.handle_command(%{state: "Flicker"}, select)
    assert select.changes[:state] == "Flicker"
    assert Scene.get(scene).effect == HomeLed.Effects.Flicker
    Process.sleep(80)
    assert {:frame, _} = FakeStrip.shown(strip)

    light |> commit() |> then(&StripLight.handle_command(%{state: false}, &1))
    assert FakeStrip.shown(strip) == {:color, {0, 0, 0}}
  end
end
