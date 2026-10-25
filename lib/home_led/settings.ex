defmodule HomeLed.Settings do
  @moduledoc """
  Settings that survive reboots: a `PropertyTable` persisted under
  `config :home_led, :settings_dir` (`/data/home_led` on the device).

    * `["leds", "count"]` - how many LEDs the strip is driven with. When nothing has been
      persisted yet it is 1, so a fresh device lights a single pixel rather than a blind
      guess at a strip length.
    * `["leds", "color_order"]` - the channel order the strip's chips expect, `:grb`
      (WS2812) by default; the orders ending in `w` are for RGBW chips such as the SK6812.
      See `t:HomeLed.Color.order/0`.
    * `["leds", "disabled"]` - ranges of LEDs the strip leaves dark, `{from, to}` tuples
      of 1-indexed positions (`HomeLed.LedRanges`), none by default. For a strip with a
      dead or unwanted stretch of pixels.
    * `["light", "scene"]` - what the strip shows (`HomeLed.Scene`): on/off, colour,
      brightness and effect, so a power cycle brings the same light back.

  Set them from IEx with `HomeLed.set_led_count/1`, `HomeLed.set_color_order/1` and
  `HomeLed.set_disabled_leds/1`;
  changes are written to disk at once and broadcast to subscribers (`subscribe/0` gets
  `%PropertyTable.Event{}`s), which is how `HomeLed.Strip` repaints.
  """

  @table __MODULE__
  @count_key ["leds", "count"]
  @order_key ["leds", "color_order"]
  @disabled_key ["leds", "disabled"]
  @scene_key ["light", "scene"]
  @default_count 1
  @default_order :grb
  @default_disabled []
  @orders HomeLed.Color.orders()

  alias HomeLed.LedRanges

  @doc false
  def child_spec(opts) do
    dir = Keyword.get_lazy(opts, :dir, fn -> Application.fetch_env!(:home_led, :settings_dir) end)
    File.mkdir_p!(dir)

    PropertyTable.child_spec(
      name: @table,
      # Used only when no snapshot can be loaded from `dir`.
      properties: [
        {@count_key, @default_count},
        {@order_key, @default_order},
        {@disabled_key, @default_disabled},
        {@scene_key, HomeLed.Scene.default()}
      ],
      persist_data_path: dir
    )
  end

  @doc "The table's name, for `PropertyTable` calls and subscriptions."
  def table, do: @table

  @doc "The property that holds the LED count."
  def count_key, do: @count_key

  @doc "The property that holds the colour order."
  def order_key, do: @order_key

  @doc "The property that holds the disabled LED ranges."
  def disabled_key, do: @disabled_key

  @doc "The colour orders a strip can have."
  def orders, do: @orders

  @doc "How many pixels the strip is driven with (default #{@default_count})."
  @spec led_count() :: pos_integer()
  def led_count do
    case PropertyTable.get(@table, @count_key, @default_count) do
      n when is_integer(n) and n > 0 -> n
      _ -> @default_count
    end
  end

  @doc "Set and persist the LED count."
  @spec set_led_count(pos_integer()) :: :ok
  def set_led_count(count) when is_integer(count) and count > 0 do
    :ok = PropertyTable.put(@table, @count_key, count)
    PropertyTable.flush_to_disk(@table)
  end

  @doc "The strip's channel order (default `#{inspect(@default_order)}`)."
  @spec color_order() :: HomeLed.Color.order()
  def color_order do
    case PropertyTable.get(@table, @order_key, @default_order) do
      order when order in @orders -> order
      _ -> @default_order
    end
  end

  @doc "Set and persist the channel order, one of `orders/0`."
  @spec set_color_order(HomeLed.Color.order()) :: :ok
  def set_color_order(order) when order in @orders do
    :ok = PropertyTable.put(@table, @order_key, order)
    PropertyTable.flush_to_disk(@table)
  end

  @doc "The LED ranges the strip leaves dark, sorted `{from, to}` tuples (default none)."
  @spec disabled_ranges() :: HomeLed.LedRanges.ranges()
  def disabled_ranges do
    case PropertyTable.get(@table, @disabled_key, @default_disabled) do
      ranges when is_list(ranges) ->
        if LedRanges.valid?(ranges), do: ranges, else: @default_disabled

      _ ->
        @default_disabled
    end
  end

  @doc """
  Set and persist the disabled LED ranges: a string as `HomeLed.LedRanges.parse/1` takes
  it (`"3-8, 10-200"`), or the `{from, to}` tuples. Invalid or overlapping ranges are
  an error and leave the setting alone.
  """
  @spec set_disabled_ranges(String.t() | HomeLed.LedRanges.ranges()) ::
          :ok | {:error, String.t()}
  def set_disabled_ranges(text) when is_binary(text) do
    with {:ok, ranges} <- LedRanges.parse(text), do: set_disabled_ranges(ranges)
  end

  def set_disabled_ranges(ranges) when is_list(ranges) do
    if LedRanges.valid?(ranges) do
      :ok = PropertyTable.put(@table, @disabled_key, Enum.sort(ranges))
      PropertyTable.flush_to_disk(@table)
    else
      {:error, "invalid or overlapping LED ranges"}
    end
  end

  @doc "The persisted scene, or the default one (see `HomeLed.Scene`)."
  @spec scene() :: HomeLed.Scene.t()
  def scene do
    default = HomeLed.Scene.default()

    case PropertyTable.get(@table, @scene_key, default) do
      %{on: on, color: {_, _, _}, brightness: b, effect: effect} = scene
      when is_boolean(on) and is_number(b) ->
        if HomeLed.Effects.valid?(effect), do: scene, else: %{scene | effect: :solid}

      _ ->
        default
    end
  end

  @doc "Persist the scene."
  @spec put_scene(HomeLed.Scene.t()) :: :ok
  def put_scene(scene) when is_map(scene) do
    :ok = PropertyTable.put(@table, @scene_key, scene)
    PropertyTable.flush_to_disk(@table)
  end

  @doc "Subscribe the caller to LED count, colour order and disabled range changes."
  @spec subscribe() :: :ok
  def subscribe, do: PropertyTable.subscribe(@table, ["leds"])
end
