defmodule HomeLed.MixProject do
  use Mix.Project

  @app :home_led
  @version "0.1.0"
  @all_targets [
    :bbb,
    :mangopi_mq_pro,
    :qemu_aarch64,
    :rpi,
    :rpi0,
    :rpi0_2,
    :rpi2,
    :rpi3,
    :rpi4,
    :rpi5,
    :trellis,
    :x86_64
  ]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.20",
      archives: [nerves_bootstrap: "~> 1.17"],
      listeners: listeners(Mix.target(), Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_ignore_filters: [~r"test/support/"],
      releases: [{@app, release()}]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {HomeLed.Application, []}
    ]
  end

  def cli do
    [preferred_targets: [run: :host, test: :host]]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Dependencies for all targets
      {:nerves, "~> 1.13", runtime: false},
      {:shoehorn, "~> 0.9.1"},
      {:logger_backends, "~> 1.0"},
      {:ring_logger, "~> 0.11.0"},
      {:toolshed, "~> 0.5.0"},

      # Allow Nerves.Runtime on host to support development, testing and CI.
      # See config/host.exs for usage.
      {:nerves_runtime, "~> 0.13.12"},

      # Persisted settings (how many LEDs the strip has). Also a vintage_net dep.
      {:property_table, "~> 0.3.4"},

      # LED hardware. Both compile on a Linux host too, which keeps the driver
      # modules warning-free there; they only open devices on the target.
      {:circuits_spi, "~> 2.2"},
      {:circuits_gpio, "~> 2.3"},

      # Home Assistant through MQTT discovery. Homex main has the light entity
      # with rgb colour (hex 0.1.2 only has brightness); pinned to a commit since
      # main is mid-refactor and changes entity ids.
      {:homex, github: "kevinschweikert/homex", ref: "ed16b96cf39e45e0a267e6171815ba9ca698fb1f"},
      # Homex's ESPHome adapter does not compile without espex even though it is
      # optional there (kevinschweikert/homex#70). Not used; drop when that is fixed.
      {:espex, "~> 0.9.0"},
      # emqtt from git so its rebar.config.script honours BUILD_WITHOUT_QUIC and
      # drops the quicer C NIF (needs cmake, and no QUIC broker here anyway).
      {:emqtt,
       github: "emqx/emqtt",
       tag: "1.14.7",
       override: true,
       system_env: [{"BUILD_WITHOUT_QUIC", "1"}]},

      # The home cluster library, vending the strip as a :light capability.
      # `runtime: false` keeps it out of this app's `applications`, so the boot
      # script does not start it: it must start after distribution is up (it
      # keys :pg groups on node()), and distribution needs an IP address. The
      # release still includes it (`applications:` in release/0) and
      # HomeLed.Distribution starts it. Target-only, as in home_base's own
      # nerves/home_node: compiling it on the host pulls x86 precompiled
      # libraries into deps/bundlex/priv, which is shared with target builds.
      {:home_base, path: "../home_base", runtime: false, targets: @all_targets},

      # Dependencies for all targets except :host
      {:nerves_pack, "~> 0.7.1", targets: @all_targets},

      # Dependencies for specific targets
      # NOTE: It's generally low risk and recommended to follow minor version
      # bumps to Nerves systems. Since these include Linux kernel and Erlang
      # version updates, please review their release notes in case
      # changes to your application are needed.
      {:nerves_system_bbb, "~> 2.19", runtime: false, targets: :bbb},
      {:nerves_system_mangopi_mq_pro, "~> 0.6", runtime: false, targets: :mangopi_mq_pro},
      {:nerves_system_qemu_aarch64, "~> 0.1", runtime: false, targets: :qemu_aarch64},
      {:nerves_system_rpi, "~> 2.0", runtime: false, targets: :rpi},
      {:nerves_system_rpi0, "~> 2.0", runtime: false, targets: :rpi0},
      {:nerves_system_rpi0_2, "~> 2.0", runtime: false, targets: :rpi0_2},
      {:nerves_system_rpi2, "~> 2.0", runtime: false, targets: :rpi2},
      {:nerves_system_rpi3, "~> 2.0", runtime: false, targets: :rpi3},
      {:nerves_system_rpi4, "~> 2.0", runtime: false, targets: :rpi4},
      {:nerves_system_rpi5, "~> 2.0", runtime: false, targets: :rpi5},
      {:nerves_system_trellis, "~> 0.4", runtime: false, targets: :trellis},
      {:nerves_system_x86_64, "~> 1.24", runtime: false, targets: :x86_64}
    ]
  end

  def release do
    [
      overwrite: true,
      # The shared home cluster cookie: every home_base node uses it, so this
      # device can join the cluster. Distribution itself is started at runtime by
      # HomeLed.Distribution once the network has an address.
      cookie: "home_cluster_cookie",
      # Loaded, not started, at boot: HomeLed.Distribution starts it after Node.start/2.
      applications: [home_base: :load],
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble, &prune_native/1],
      strip_beams: Mix.env() == :prod or [keep: ["Docs"]]
    ]
  end

  # Drop native files the target doesn't load (see rel/prune_native.exs). home_base
  # brings Membrane's precompiled ffmpeg/opus/portaudio and emerge's NIF for the host
  # as well as the target; without this the rootfs does not fit and Nerves' scrub
  # rejects the host binaries.
  defp prune_native(release) do
    Code.require_file("rel/prune_native.exs", __DIR__)
    HomeLed.PruneNative.run(release)
  end

  # Uncomment the following line if using Phoenix > 1.8.
  # defp listeners(:host, :dev), do: [Phoenix.CodeReloader]
  defp listeners(_, _), do: []
end
