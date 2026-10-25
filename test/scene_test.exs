defmodule HomeLed.SceneTest do
  use ExUnit.Case, async: true

  alias HomeLed.{FakeStrip, Scene}

  setup do
    {:ok, strip} = FakeStrip.start_link()
    {:ok, scene} = Scene.start_link(strip: strip, persist: false, name: nil)
    {:ok, strip: strip, scene: scene}
  end

  test "starts off and paints the colour at the brightness when on", %{strip: strip, scene: scene} do
    assert Scene.get(scene) == Scene.default()
    assert FakeStrip.shown(strip) == {:color, {0, 0, 0}}

    :ok = Scene.set_color(scene, {1.0, 0.0, 0.0})
    :ok = Scene.set_brightness(scene, 0.5)
    assert FakeStrip.shown(strip) == {:color, {0, 0, 0}}, "still off"

    :ok = Scene.set_on(scene, true)
    assert FakeStrip.shown(strip) == {:color, {128, 0, 0}}
    :ok = Scene.set_brightness(scene, 1)
    assert FakeStrip.shown(strip) == {:color, {255, 0, 0}}

    assert Scene.get(scene) == %{
             on: true,
             color: {1.0, 0.0, 0.0},
             brightness: 1.0,
             effect: :solid
           }
  end

  test "an effect paints frames while on and stops when off or solid", %{
    strip: strip,
    scene: scene
  } do
    :ok = Scene.set_on(scene, true)
    :ok = Scene.set_color(scene, {1.0, 0.3, 0.0})
    assert :ok = Scene.set_effect(scene, HomeLed.Effects.Flicker)
    Process.sleep(80)
    assert {:frame, <<_r, _g, 0>>} = FakeStrip.shown(strip)

    :ok = Scene.set_on(scene, false)
    assert FakeStrip.shown(strip) == {:color, {0, 0, 0}}
    Process.sleep(80)
    assert FakeStrip.shown(strip) == {:color, {0, 0, 0}}, "no frame after off"

    :ok = Scene.set_on(scene, true)
    Process.sleep(80)
    assert {:frame, _} = FakeStrip.shown(strip)
    :ok = Scene.set_effect(scene, :solid)
    assert FakeStrip.shown(strip) == {:color, {255, 77, 0}}
    Process.sleep(80)
    assert FakeStrip.shown(strip) == {:color, {255, 77, 0}}
  end

  test "rejects unknown effects", %{scene: scene} do
    assert {:error, :unknown_effect} = Scene.set_effect(scene, :disco)
  end
end
