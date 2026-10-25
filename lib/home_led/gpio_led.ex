defmodule HomeLed.GpioLed do
  @moduledoc """
  A plain LED on one GPIO pin: on or off, nothing else. The non-addressable counterpart
  of `HomeLed.Strip`, with the same `Home.Light.Driver` functions (not declared as a
  behaviour, home_base being target-only) so it can be vended as a `:light` with
  `color_modes: [:on_off]`. Any colour but black turns it on.

  Started only when `config :home_led, gpio_led: pin` names a pin.
  """
  use GenServer
  require Logger

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  ## Home.Light.Driver

  def info(_server), do: %{addressable: false, color_modes: [:on_off]}

  def set_color(server \\ __MODULE__, {r, g, b}),
    do: GenServer.call(server, {:set, r + g + b > 0})

  def set_frame(_server \\ __MODULE__, _frame), do: {:error, :not_addressable}

  def off(server \\ __MODULE__), do: GenServer.call(server, {:set, false})

  @doc "Turn the LED on or off."
  @spec set(GenServer.server(), boolean()) :: :ok
  def set(server \\ __MODULE__, on?) when is_boolean(on?), do: GenServer.call(server, {:set, on?})

  @doc "Whether the LED is on."
  @spec on?(GenServer.server()) :: boolean()
  def on?(server \\ __MODULE__), do: GenServer.call(server, :on?)

  ## Server

  @impl true
  def init(opts) do
    pin = Keyword.fetch!(opts, :pin)

    gpio =
      case Circuits.GPIO.open(pin, :output, initial_value: 0) do
        {:ok, gpio} ->
          gpio

        {:error, reason} ->
          Logger.warning("GPIO #{inspect(pin)} unavailable (#{inspect(reason)}); LED runs blind")
          nil
      end

    {:ok, %{gpio: gpio, on?: false}}
  end

  @impl true
  def handle_call({:set, on?}, _from, state) do
    if state.gpio, do: Circuits.GPIO.write(state.gpio, if(on?, do: 1, else: 0))
    {:reply, :ok, %{state | on?: on?}}
  end

  def handle_call(:on?, _from, state), do: {:reply, state.on?, state}
end
