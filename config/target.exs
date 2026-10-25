import Config

# Use shoehorn to start the main application. See the shoehorn
# library documentation for more control in ordering how OTP
# applications are started and handling failures.

config :shoehorn, init: [:nerves_runtime, :nerves_pack]

# Enable the system startup guard to check that all OTP applications
# started. If they didn't and you're on a Nerves system that supports
# test runs of new firmware, the firmware will automatically roll
# back to the previous version. Delete this if implementing your own
# way of validating that firmware is good.
config :nerves_runtime, startup_guard_enabled: true

# Erlinit can be configured without a rootfs_overlay. See
# https://github.com/nerves-project/erlinit/ for more information on
# configuring erlinit.

# Advance the system clock on devices without a real-time clock.
config :nerves, :erlinit, update_clock: true

# Default to not starting so that the console logger isn't started. See
# runtime.exs for logger configuration.
config :logger, :default_handler, false

# Configure the device for SSH IEx prompt access and firmware updates
#
# * See https://nerves-ssh.hexdocs.pm/readme.html for general SSH configuration
# * See https://ssh-subsystem-fwup.hexdocs.pm/readme.html for firmware updates

keys =
  System.user_home!()
  |> Path.join(".ssh/id_{rsa,ecdsa,ed25519}.pub")
  |> Path.wildcard()

if keys == [],
  do:
    Mix.raise("""
    No SSH public keys found in ~/.ssh. An ssh authorized key is needed to
    log into the Nerves device and update firmware on it using ssh.
    See your project's config.exs for this error message.
    """)

config :nerves_ssh,
  authorized_keys: Enum.map(keys, &File.read!/1)

# Secrets come from the environment at compile time (.envrc, untracked; see
# .envrc.example). Refuse to build firmware without them: a device flashed without
# WiFi credentials is unreachable and has to be re-flashed by hand, and one without
# broker credentials never shows up in Home Assistant.
env! = fn name ->
  case System.get_env(name) do
    value when is_binary(value) and value != "" ->
      value

    _ ->
      Mix.raise("""
      Refusing to build firmware for target #{Mix.target()}: #{name} is not set.

      It comes from .envrc. Run `direnv allow` (or `source .envrc`) and try again.
      See .envrc.example for every variable the firmware needs.
      """)
  end
end

# WiFi networks: HOME_LED_WIFI_SSID_1/PSK_1, _2, ... until a gap. wpa_supplicant joins
# whichever it sees, preferring the earlier ones (higher priority) when several are in
# range.
wifi_networks =
  Stream.iterate(1, &(&1 + 1))
  |> Enum.reduce_while([], fn n, acc ->
    case System.get_env("HOME_LED_WIFI_SSID_#{n}") do
      ssid when is_binary(ssid) and ssid != "" ->
        network = %{key_mgmt: :wpa_psk, ssid: ssid, psk: env!.("HOME_LED_WIFI_PSK_#{n}")}
        {:cont, [network | acc]}

      _ ->
        {:halt, Enum.reverse(acc)}
    end
  end)
  |> then(fn networks ->
    count = length(networks)
    Enum.with_index(networks, fn network, i -> Map.put(network, :priority, count - i) end)
  end)

if wifi_networks == [], do: env!.("HOME_LED_WIFI_SSID_1")

# Configure the network using vintage_net
#
# See https://github.com/nerves-networking/vintage_net for more information
config :vintage_net,
  regulatory_domain: "SE",
  config: [
    {"usb0", %{type: VintageNetDirect}},
    {"eth0",
     %{
       type: VintageNetEthernet,
       ipv4: %{method: :dhcp}
     }},
    {"wlan0",
     %{
       type: VintageNetWiFi,
       vintage_net_wifi: %{networks: wifi_networks},
       ipv4: %{method: :dhcp}
     }}
  ]

config :mdns_lite,
  # The `hosts` key specifies what hostnames mdns_lite advertises.  `:hostname`
  # advertises the device's hostname.local. For the official Nerves systems, this
  # is "nerves-<4 digit serial#>.local". "home-led" is advertised for convenience;
  # with several of these on one network, drop it.
  hosts: [:hostname, "home-led"],
  ttl: 120,

  # Advertise the following services over mDNS.
  services: [
    %{
      protocol: "ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "sftp-ssh",
      transport: "tcp",
      port: 22
    }
  ]

# Home Assistant, through Homex and the MQTT broker (see HomeLed.Application).
config :home_led, :mqtt,
  host: env!.("MQTT_HOST"),
  port: String.to_integer(System.get_env("MQTT_PORT", "1883")),
  username: env!.("MQTT_USERNAME"),
  password: env!.("MQTT_PASSWORD")

# The LED hardware.
#
#   * strip: WS281x pixels on SPI (4 SPI bits per data bit at 3.2 MHz, the format Fledex
#     uses too). How many pixels there are and their channel order (:grb for WS2812)
#     are persisted settings (HomeLed.Settings; defaults 1 and :grb), not config.
#     `devices` are tried in order; spidev0.0 is the Pi's CE0 (GPIO 8), MOSI on GPIO 10
#     is the data line.
#   * gpio_led: a plain on/off LED (not addressable) on a GPIO pin, exposed as a second
#     light. nil for none.
config :home_led,
  settings_dir: "/data/home_led",
  strip: [devices: ["spidev0.0", "spidev0.1"]],
  gpio_led: nil

# Home cluster.
#
# HomeLed.Distribution waits for an IPv4 address on one of `interfaces`, starts
# distribution as `home@<address>`, then starts home_base. The strip is vended as a
# :light capability (see Home.Light); the GPIO LED is added at boot when configured.
config :home_led, :distribution, interfaces: ["wlan0", "eth0"], basename: "home"

config :home_base,
  data_dir: "/data/home",
  capabilities: [
    %{
      id: "led0",
      kind: :light,
      adapter: {Home.Adapters.Light, driver: {HomeLed.Strip, HomeLed.Strip}},
      meta: %{addressable: true, color_modes: [:rgb]}
    }
  ],
  # No peer discovery on the LAN yet: list the other home nodes here, e.g.
  # nodes: [:"home@192.168.2.50"]. With Tailscale this becomes Home.Cluster.Tailscale.
  cluster: [backend: {Home.Cluster.Static, nodes: []}, interval: 5_000]

# Import target specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
# Uncomment to use target specific configurations

# import_config "#{Mix.target()}.exs"
