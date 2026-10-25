defmodule HomeLed.Strip do
  @moduledoc """
  Owns the SPI bus and drives the WS281x strip.

  The strip is `HomeLed.Settings.led_count/0` pixels long (default 1, persisted). A
  colour fills every pixel; a frame paints them one by one and is padded with black or
  cut to the strip's length. Frames are packed into the strip's channel order
  (`HomeLed.Settings.color_order/0`, persisted, `:grb` for WS2812, `:grbw` for SK6812 RGBW
  with the white channel derived from the colour), encoded 4 SPI bits per data bit
  (`HomeLed.SpiEncoder`) and written in one transfer.

  The last thing shown is kept, so a change of LED count or colour order repaints
  straight away, and the strip can be asked what it shows (`current/1`).

  This is also the `Home.Light.Driver` behind the `:light` capability the node vends
  (`info/1`, `set_color/2`, `set_frame/2`, `off/1`): the manifest names
  `{HomeLed.Strip, HomeLed.Strip}` and cluster peers reach it through `Home.Light`. The
  behaviour is not declared because home_base is a target-only dependency.

  Without SPI hardware (no `spidev`, or on a host) the strip runs blind: everything is
  accepted and remembered, nothing is written.
  """
  use GenServer
  require Logger

  alias HomeLed.{Color, Settings, SpiEncoder}

  @bytes_per_led 3
  # Default size of the spidev transfer buffer on the Pi. Frames above this fail
  # to transmit unless the kernel is booted with a larger spidev.bufsiz.
  @spidev_bufsiz 4096

  @spi_opts [speed_hz: 3_200_000, mode: 0, bits_per_word: 8, delay_us: 10, lsb_first: false]

  @typedoc "What the strip shows: one colour everywhere, or a frame of RGB bytes."
  @type shown :: {:color, Color.rgb()} | {:frame, binary()}

  @doc """
  Options: `:devices` (spidev names tried in order, default from
  `config :home_led, :strip`) and `:name`.
  """
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  ## Home.Light.Driver

  @doc "What the strip can do; `leds` is the current count."
  def info(server \\ __MODULE__), do: GenServer.call(server, :info)

  @doc "Show one colour, `{r, g, b}` bytes, on every pixel."
  @spec set_color(GenServer.server(), Color.rgb()) :: :ok
  def set_color(server \\ __MODULE__, {r, g, b} = rgb)
      when r in 0..255 and g in 0..255 and b in 0..255,
      do: GenServer.call(server, {:show, {:color, rgb}})

  @doc "Paint pixels from RGB bytes, three per pixel. Short frames leave the rest dark."
  @spec set_frame(GenServer.server(), binary()) :: :ok
  def set_frame(server \\ __MODULE__, frame)
      when is_binary(frame) and rem(byte_size(frame), @bytes_per_led) == 0,
      do: GenServer.call(server, {:show, {:frame, frame}})

  @doc "Every pixel off."
  @spec off(GenServer.server()) :: :ok
  def off(server \\ __MODULE__), do: set_color(server, {0, 0, 0})

  @doc "What the strip currently shows."
  @spec current(GenServer.server()) :: shown()
  def current(server \\ __MODULE__), do: GenServer.call(server, :current)

  ## Server

  @impl true
  def init(opts) do
    config = Application.get_env(:home_led, :strip, [])
    devices = Keyword.get(opts, :devices, Keyword.get(config, :devices, ["spidev0.0"]))

    Settings.subscribe()

    state = %{
      spi: open_spi(devices),
      order: Settings.color_order(),
      count: Settings.led_count(),
      shown: {:color, {0, 0, 0}}
    }

    {:ok, state, {:continue, :paint}}
  end

  @impl true
  def handle_continue(:paint, state) do
    paint(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:info, _from, state) do
    {:reply, %{addressable: true, color_modes: [:rgb], leds: state.count}, state}
  end

  def handle_call(:current, _from, state), do: {:reply, state.shown, state}

  def handle_call({:show, shown}, _from, state) do
    state = %{state | shown: shown}
    paint(state)
    {:reply, :ok, state}
  end

  # A setting changed (HomeLed.Settings): repaint with it.
  @impl true
  def handle_info(%PropertyTable.Event{property: ["leds", "count"], value: count}, state)
      when is_integer(count) and count > 0 and count != state.count do
    Logger.info("strip is now #{count} LEDs long")
    state = %{state | count: count}
    paint(state)
    {:noreply, state}
  end

  def handle_info(%PropertyTable.Event{property: ["leds", "color_order"], value: order}, state)
      when is_atom(order) and order != state.order do
    if order in Settings.orders() do
      Logger.info("strip colour order is now #{order}")
      state = %{state | order: order}
      paint(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## Internals

  defp open_spi([]) do
    Logger.warning("no SPI device available; the strip runs blind")
    nil
  end

  defp open_spi([device | rest]) do
    case Circuits.SPI.open(device, @spi_opts) do
      {:ok, spi} ->
        Logger.info("strip on #{device}")
        spi

      {:error, reason} ->
        Logger.debug("#{device}: #{inspect(reason)}")
        open_spi(rest)
    end
  end

  defp paint(%{spi: nil}), do: :ok

  defp paint(%{spi: spi, order: order, count: count, shown: shown}) do
    rgb = frame(shown, count)
    buffer = SpiEncoder.encode(Color.pack_frame(rgb, order))
    warn_if_oversized(buffer)

    case Circuits.SPI.transfer(spi, buffer) do
      {:ok, _received} -> :ok
      {:error, reason} -> Logger.error("SPI transfer failed: #{inspect(reason)}")
    end
  end

  # the RGB bytes for the whole strip: a colour repeated, or a frame fitted to length
  defp frame({:color, {r, g, b}}, count), do: :binary.copy(<<r, g, b>>, count)

  defp frame({:frame, frame}, count) do
    wanted = count * @bytes_per_led

    case byte_size(frame) do
      ^wanted -> frame
      size when size > wanted -> binary_part(frame, 0, wanted)
      size -> <<frame::binary, 0::size(wanted - size)-unit(8)>>
    end
  end

  # Logged once per offending size so a stream of frames does not flood the log.
  defp warn_if_oversized(buffer) when byte_size(buffer) > @spidev_bufsiz do
    size = byte_size(buffer)

    unless Process.get({:spi_oversize_warned, size}) do
      Process.put({:spi_oversize_warned, size}, true)

      Logger.error(
        "SPI frame of #{size} bytes exceeds the default spidev buffer of #{@spidev_bufsiz}. " <>
          "Boot with spidev.bufsiz=65536 on the kernel command line or drive fewer LEDs."
      )
    end
  end

  defp warn_if_oversized(_buffer), do: :ok
end
