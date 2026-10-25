defmodule HomeLed.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # Children for all targets
        HomeLed.Settings
      ] ++ target_children()

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HomeLed.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # List all child processes to be supervised
  if Mix.target() == :host do
    defp target_children() do
      [
        # Children that only run on the host during development or test.
        # In general, prefer using `config/host.exs` for differences.
      ]
    end
  else
    defp target_children() do
      gpio_led = Application.get_env(:home_led, :gpio_led)

      [HomeLed.Strip, HomeLed.Scene] ++
        if(gpio_led, do: [{HomeLed.GpioLed, pin: gpio_led}], else: []) ++
        homex_children(gpio_led) ++
        [{HomeLed.Distribution, Application.get_env(:home_led, :distribution, [])}]
    end

    # Homex (MQTT discovery) under its own supervisor, so a broker that is down or
    # refusing the credentials cannot take the lights with it.
    defp homex_children(gpio_led) do
      case Application.get_env(:home_led, :mqtt) do
        nil ->
          require Logger
          Logger.warning("no MQTT broker configured; not registering with Home Assistant")
          []

        broker ->
          entities =
            [
              HomeLed.Entities.StripLight,
              HomeLed.Entities.StripEffect,
              HomeLed.Entities.LedCount,
              HomeLed.Entities.ColorOrder
            ] ++
              if(gpio_led, do: [HomeLed.Entities.GpioLight], else: [])

          homex =
            {Homex,
             id: Homex.hostname(),
             devices: [
               default: [
                 name: "Home LED #{Homex.hostname()}",
                 manufacturer: "Underjord",
                 model: "home_led"
               ]
             ],
             origin: [
               name: "home_led",
               sw_version: Application.spec(:home_led, :vsn) |> to_string()
             ],
             adapters: [{Homex.Adapter.MQTT, broker: broker}],
             entities: entities}

          [
            %{
              id: HomeLed.HomexSupervisor,
              type: :supervisor,
              start:
                {Supervisor, :start_link,
                 [
                   [homex],
                   [
                     strategy: :one_for_one,
                     name: HomeLed.HomexSupervisor,
                     max_restarts: 5,
                     max_seconds: 300
                   ]
                 ]}
            }
          ]
      end
    end
  end
end
