defmodule HomeLed.Scene do
  @moduledoc """
  What the strip shows, and the one process that decides it: on or off, a colour, a
  brightness and an effect (`HomeLed.Effects`). Home Assistant's light and effect
  entities set these; the scene paints `HomeLed.Strip`, running the effect at its frame
  rate while the light is on.

  The scene is persisted (`HomeLed.Settings.scene/0`), so a lantern that loses power
  comes back flickering in the same orange. Subscribers (`subscribe/1`) get
  `{:scene, scene}` on every change, which is how the entities keep Home Assistant in
  step with changes made here, from IEx or by the restored scene at boot.

  The colour is kept as Home Assistant hands it over: a hue with its brightest component
  at `1.0`, and the brightness apart (`HomeLed.Color.emitted/3`).

  A cluster peer painting the strip through its `Home.Light` lease is not stopped: while
  an effect runs, the next tick paints over it; with a solid colour the scene repaints
  only when something here changes.
  """
  use GenServer

  alias HomeLed.{Color, Effects, Settings, Strip}

  @type hue :: {float(), float(), float()}
  @type t :: %{on: boolean(), color: hue(), brightness: float(), effect: Effects.effect()}

  @default %{on: false, color: {1.0, 1.0, 1.0}, brightness: 1.0, effect: :solid}

  @doc """
  Options: `:strip` (the `HomeLed.Strip` to paint, default `HomeLed.Strip`), `:persist`
  (read and write `HomeLed.Settings.scene/0`, default true), `:name`.
  """
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "The scene as set: `%{on, color, brightness, effect}`."
  @spec get(GenServer.server()) :: t()
  def get(server \\ __MODULE__), do: GenServer.call(server, :get)

  @doc "The scene a fresh device starts with."
  @spec default() :: t()
  def default, do: @default

  @spec set_on(GenServer.server(), boolean()) :: :ok
  def set_on(server \\ __MODULE__, on?) when is_boolean(on?), do: set(server, %{on: on?})

  @doc "The hue, components `0.0..1.0`, as `Homex.Entity.Light` keeps it."
  @spec set_color(GenServer.server(), hue()) :: :ok
  def set_color(server \\ __MODULE__, {r, g, b} = hue)
      when r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1,
      do: set(server, %{color: hue})

  @spec set_brightness(GenServer.server(), number()) :: :ok
  def set_brightness(server \\ __MODULE__, brightness)
      when brightness >= 0 and brightness <= 1,
      do: set(server, %{brightness: brightness / 1})

  @spec set_effect(GenServer.server(), Effects.effect()) :: :ok | {:error, :unknown_effect}
  def set_effect(server \\ __MODULE__, effect) do
    if Effects.valid?(effect), do: set(server, %{effect: effect}), else: {:error, :unknown_effect}
  end

  defp set(server, changes), do: GenServer.call(server, {:set, changes})

  @doc "Send the caller `{:scene, scene}` now and after every change, until it exits."
  @spec subscribe(GenServer.server()) :: :ok
  def subscribe(server \\ __MODULE__), do: GenServer.call(server, {:subscribe, self()})

  ## Server

  @impl true
  def init(opts) do
    persist? = Keyword.get(opts, :persist, true)
    scene = if persist?, do: Settings.scene(), else: @default

    state = %{
      strip: Keyword.get(opts, :strip, Strip),
      persist?: persist?,
      scene: scene,
      run: nil,
      subscribers: %{}
    }

    {:ok, state, {:continue, :paint}}
  end

  @impl true
  def handle_continue(:paint, state), do: {:noreply, paint(state)}

  @impl true
  def handle_call(:get, _from, state), do: {:reply, state.scene, state}

  def handle_call({:set, changes}, _from, state) do
    scene = Map.merge(state.scene, changes)
    if state.persist?, do: Settings.put_scene(scene)
    for {pid, _ref} <- state.subscribers, do: send(pid, {:scene, scene})
    {:reply, :ok, paint(%{state | scene: scene})}
  end

  def handle_call({:subscribe, pid}, _from, state) do
    send(pid, {:scene, state.scene})

    subscribers =
      Map.put_new_lazy(state.subscribers, pid, fn -> Process.monitor(pid) end)

    {:reply, :ok, %{state | subscribers: subscribers}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state),
    do: {:noreply, %{state | subscribers: Map.delete(state.subscribers, pid)}}

  def handle_info(:tick, %{run: nil} = state), do: {:noreply, state}

  def handle_info(:tick, %{run: run} = state) do
    ctx = context(state)
    {frame, estate} = run.effect.frame(run.estate, ctx)
    Strip.set_frame(state.strip, frame)
    timer = Process.send_after(self(), :tick, div(1_000, run.effect.fps()))
    {:noreply, %{state | run: %{run | estate: estate, timer: timer}}}
  end

  ## Painting

  # off, or solid: paint once and stop any effect; otherwise (re)start the effect
  defp paint(%{scene: %{on: false}} = state) do
    Strip.off(state.strip)
    stop_run(state)
  end

  defp paint(%{scene: %{effect: :solid}} = state) do
    Strip.set_color(state.strip, emitted(state.scene))
    stop_run(state)
  end

  defp paint(%{scene: %{effect: effect}, run: %{effect: effect}} = state) do
    # the same effect keeps running; the next tick picks up the new colour/brightness
    state
  end

  defp paint(%{scene: %{effect: effect}} = state) do
    state = stop_run(state)
    started = System.monotonic_time(:millisecond)
    run = %{effect: effect, started: started, estate: nil, timer: nil}
    state = %{state | run: run}
    run = %{run | estate: effect.init(context(state))}
    send(self(), :tick)
    %{state | run: run}
  end

  defp stop_run(%{run: nil} = state), do: state

  defp stop_run(%{run: %{timer: timer}} = state) do
    if timer, do: Process.cancel_timer(timer)
    %{state | run: nil}
  end

  defp context(%{scene: scene, run: run}) do
    %{
      count: Settings.led_count(),
      color: emitted(scene),
      brightness: scene.brightness,
      time_ms: if(run, do: System.monotonic_time(:millisecond) - run.started, else: 0)
    }
  end

  defp emitted(%{color: hue, brightness: brightness, on: on?}),
    do: Color.emitted(hue, brightness, on?)
end
