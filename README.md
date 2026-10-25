# HomeLed

Nerves firmware for a WS281x LED strip (and, optionally, a plain LED on a GPIO) that is

- a **Home Assistant light with effects**, found through MQTT discovery with
  [Homex](https://github.com/kevinschweikert/homex): an RGB light for the strip
  (`HomeLed.Entities.StripLight`), an effect select next to it
  (`HomeLed.Entities.StripEffect`: Solid, Flicker, Breathe, Rainbow), a number for the LED
  count and a select for the colour order (`HomeLed.Entities.LedCount`,
  `HomeLed.Entities.ColorOrder`), and an on/off light for the GPIO LED
  (`HomeLed.Entities.GpioLight`);
- a **`:light` capability on the home cluster**, through
  [`home_base`](../home_base) (`Home.Light`): any node in the cluster can lease the strip
  and paint it, one colour or pixel by pixel.

The strip is driven over SPI with the raw WS281x bit pattern Fledex uses (4 SPI bits per
data bit at 3.2 MHz), as in the `creature` firmware: data on MOSI (GPIO 10), `spidev0.0`.
How many pixels there are and their channel order are **persisted settings**, not config:
`HomeLed.Settings` is a `PropertyTable` under `/data/home_led`, set from Home Assistant
or IEx. A device that has never been told defaults to 1 pixel in `:grb` order (WS2812).
The light's own state (on/off, colour, brightness, effect) is persisted there too, so a
reboot brings back the last lighting instruction.
RGBW strips (SK6812 and the like) take one of the four-channel orders, `:grbw` usually;
the white LED gets the white part of the colour (`min(r, g, b)`), taken out of the three
colours, so white is white and a saturated colour leaves it dark.

```elixir
HomeLed.led_count()            # 1
HomeLed.set_led_count(60)      # persisted; the strip repaints at the new length
HomeLed.color_order()          # :grb
HomeLed.set_color_order(:grbw) # persisted too; 3-channel :rgb ... :bgr, RGBW :rgbw ... :bgrw
HomeLed.set_on(true)           # the same controls Home Assistant has
HomeLed.set_color({1.0, 0.3, 0.0})
HomeLed.set_brightness(0.8)
HomeLed.set_effect(HomeLed.Effects.Flicker)   # or :solid, Breathe, Rainbow
HomeLed.scene()                # %{on: true, color: ..., brightness: 0.8, effect: ...}
```

`HomeLed.Scene` owns what the strip shows and persists it, so a pumpkin lantern that
loses power comes back flickering in the same orange; the entities report that state to
Home Assistant at boot. Effects are `HomeLed.Effect` modules (one frame per tick, 30 fps);
`HomeLed.Effects.Flicker` is the candle for the lantern. Adding one is a module and a line
in `HomeLed.Effects`.

Targets only for now (`MIX_TARGET=rpi0_2` is what this is built for); the host target
runs the unit tests and nothing else.

## Secrets

Build-time secrets live in `.envrc`, which git ignores. Copy `.envrc.example` and fill in:

| Variable | What |
| --- | --- |
| `HOME_LED_WIFI_SSID_n` / `HOME_LED_WIFI_PSK_n` | WiFi networks, tried in order (`_1`, `_2`, ...). |
| `MQTT_HOST`, `MQTT_PORT`, `MQTT_USERNAME`, `MQTT_PASSWORD` | Home Assistant's broker, for Homex. |
| `EMERGE_PATH` | Where `scripts/vendor_emerge.sh` puts emerge (see below). |

`config/target.exs` reads them at compile time and refuses to build firmware without
them. Load them with `direnv allow` (or `source .envrc`).

## Build

```sh
direnv allow                   # or: source .envrc
scripts/vendor_emerge.sh       # once: emerge 0.5.0 + home_base's patch into $EMERGE_PATH
export MIX_TARGET=rpi0_2
mix deps.get
mix firmware
mix burn                       # or: mix upload home-led.local
```

`home_base` depends on emerge as a path dependency (hex 0.5.0 plus the Elixir-only
scene-forwarding patch in `../home_base/docs`); `scripts/vendor_emerge.sh` recreates that
checkout. The release step `rel/prune_native.exs` (from home_base's own `home_node`)
drops the precompiled native libraries the target does not load; without it the rootfs
does not fit and Nerves rejects the host binaries.

## Home Assistant

Homex registers the device as `Home LED <hostname>` with the broker from `.envrc`
(`HomeLed.Application`). The strip is one `light` with the `rgb` colour mode (Home
Assistant sets a hue and a brightness, `HomeLed.Color.emitted/3` makes the bytes) plus a
`select` for the effect. HA's MQTT light has an effect list of its own that would put the
effects in the light card; Homex's light entity does not carry it yet, hence the select.
Homex is pinned to a commit of `main`, which has the light entity with colour (hex 0.1.2
only has brightness) but is mid-refactor; a later ref may change entity ids.

## Home cluster

`HomeLed.Distribution` waits for an address on `wlan0` (then `eth0`), starts distribution
as `home@<ip>` with the shared `home_cluster_cookie`, no epmd, port 4370 (what
`home_base`'s `home_node` does), then starts `home_base` with the manifest in
`config/target.exs`:

```elixir
%{id: "led0", kind: :light,
  adapter: {Home.Adapters.Light, driver: {HomeLed.Strip, HomeLed.Strip}},
  meta: %{addressable: true, color_modes: [:rgb]}}
```

From any node in the cluster:

```elixir
[%{ref: led}] = Home.Registry.list(kind: :light)
{:ok, lease} = Home.Lease.acquire(led.ref, purpose: "doorbell")
Home.Light.info(lease)                  # %{addressable: true, color_modes: [:rgb], leds: 60}
Home.Light.set_color(lease, {255, 80, 0})
Home.Light.set_frame(lease, frame)      # RGB bytes, three per pixel
Home.Light.release(lease)
```

There is no peer discovery on the LAN yet: list the other nodes under
`config :home_base, cluster:` (`Home.Cluster.Static`).

## Hardware config

```elixir
config :home_led,
  strip: [devices: ["spidev0.0", "spidev0.1"]],   # spidev names tried in order
  gpio_led: nil     # e.g. 18: an on/off LED on GPIO 18, as a second light everywhere
```

## Tests

`mix test` on the host covers the colour arithmetic, the SPI encoding, the persisted
settings, the scene and effects against a fake strip, and the entities' handling of Homex
commands.
