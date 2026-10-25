defmodule HomeLed.SettingsTest do
  use ExUnit.Case

  alias HomeLed.Settings

  setup do
    # The application started Settings from the configured dir; this test wants a
    # fresh one so the default is observable.
    :ok = Application.stop(:home_led)
    # subscribe/0 registers in the table's Registry, which links the subscriber: the
    # table's shutdown then reaches this process as an exit signal.
    Process.flag(:trap_exit, true)

    dir =
      Path.join(System.tmp_dir!(), "home_led_settings_test_#{System.unique_integer([:positive])}")

    on_exit(fn ->
      File.rm_rf!(dir)
      {:ok, _} = Application.ensure_all_started(:home_led)
    end)

    {:ok, dir: dir}
  end

  test "defaults to one grb LED and persists new values across restarts", %{dir: dir} do
    {:ok, sup} = Supervisor.start_link([{Settings, dir: dir}], strategy: :one_for_one)
    assert Settings.led_count() == 1
    assert Settings.color_order() == :grb
    assert Settings.disabled_ranges() == []

    Settings.subscribe()
    assert :ok = Settings.set_led_count(60)
    assert_receive %PropertyTable.Event{property: ["leds", "count"], value: 60}
    assert :ok = Settings.set_color_order(:bgr)
    assert_receive %PropertyTable.Event{property: ["leds", "color_order"], value: :bgr}
    assert Settings.led_count() == 60
    assert Settings.color_order() == :bgr
    assert_raise FunctionClauseError, fn -> apply(Settings, :set_color_order, [:xyz]) end
    assert :ok = Settings.set_disabled_ranges("10-12, 3")
    assert_receive %PropertyTable.Event{property: ["leds", "disabled"], value: [{3, 3}, {10, 12}]}
    assert {:error, _} = Settings.set_disabled_ranges("3, 1-5")
    assert {:error, _} = Settings.set_disabled_ranges([{5, 1}])
    assert Settings.disabled_ranges() == [{3, 3}, {10, 12}]
    Supervisor.stop(sup)

    {:ok, sup} = Supervisor.start_link([{Settings, dir: dir}], strategy: :one_for_one)
    assert Settings.led_count() == 60
    assert Settings.color_order() == :bgr
    assert Settings.disabled_ranges() == [{3, 3}, {10, 12}]
    Supervisor.stop(sup)
  end
end
