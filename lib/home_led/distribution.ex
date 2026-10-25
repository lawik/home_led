defmodule HomeLed.Distribution do
  @moduledoc """
  Names this node after its address and then starts `home_base`.

  Waits until one of `interfaces` has an IPv4 address, starts distribution as
  `<basename>@<that address>` with the release cookie, then starts the `:home_base`
  application. home_base has to come after distribution: its `:pg` groups and node state
  are keyed on `node()`. The same pattern as `HomeNode.Distribution` in home_base's own
  Nerves project.

  When a GPIO LED is configured it is added as a runtime `:light` capability once
  home_base is up, so the manifest in config stays about the strip.

      config :home_led, :distribution, interfaces: ["wlan0", "eth0"], basename: "home"
  """
  use GenServer
  require Logger

  # home_base is a target-only dependency; its modules are not there on the host.
  @compile {:no_warn_undefined, Home.Capability}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    state = %{
      interfaces: opts |> Keyword.get(:interfaces, ["wlan0", "eth0"]) |> Enum.map(&to_charlist/1),
      basename: Keyword.get(opts, :basename, "home"),
      poll: Keyword.get(opts, :poll, 500)
    }

    {:ok, state, {:continue, :wait}}
  end

  @impl true
  def handle_continue(:wait, state), do: handle_info(:poll, state)

  @impl true
  def handle_info(:poll, state) do
    case ipv4(state.interfaces) do
      {:ok, ip} ->
        start(state, ip)
        {:noreply, state}

      :error ->
        Process.send_after(self(), :poll, state.poll)
        {:noreply, state}
    end
  end

  defp start(state, ip) do
    name = :"#{state.basename}@#{:inet.ntoa(ip)}"

    unless Node.alive?() do
      {:ok, _} = Node.start(name, :longnames)
      Logger.info("distribution started as #{name}")
    end

    media = Application.get_env(:home_base, :media, [])
    Application.put_env(:home_base, :media, Keyword.put_new(media, :ip, ip))

    {:ok, _} = Application.ensure_all_started(:home_base, :permanent)
    Logger.info("home_base started on #{node()}")
    add_gpio_light()
  end

  defp add_gpio_light do
    if Application.get_env(:home_led, :gpio_led) do
      case Home.Capability.add(%{
             id: "led1",
             kind: :light,
             adapter: {Home.Adapters.Light, driver: {HomeLed.GpioLed, HomeLed.GpioLed}},
             meta: %{addressable: false, color_modes: [:on_off]}
           }) do
        {:ok, _pid} -> :ok
        {:error, :already_exists} -> :ok
        {:error, reason} -> Logger.error("could not vend the GPIO LED: #{inspect(reason)}")
      end
    end
  end

  # the first interface, in the configured order, that has an IPv4 address
  defp ipv4(interfaces) do
    with {:ok, ifaddrs} <- :inet.getifaddrs() do
      Enum.find_value(interfaces, :error, fn interface ->
        with {_, opts} <- List.keyfind(ifaddrs, interface, 0),
             ip when is_tuple(ip) <-
               Enum.find(Keyword.get_values(opts, :addr), &(tuple_size(&1) == 4)) do
          {:ok, ip}
        else
          _ -> nil
        end
      end)
    else
      _ -> :error
    end
  end
end
