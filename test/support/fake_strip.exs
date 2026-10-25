defmodule HomeLed.FakeStrip do
  @moduledoc "Speaks HomeLed.Strip's call protocol and remembers what it was told to show."
  use GenServer
  def start_link(_ \\ []), do: GenServer.start_link(__MODULE__, nil)
  def shown(pid), do: GenServer.call(pid, :shown)
  @impl true
  def init(_), do: {:ok, nil}
  @impl true
  def handle_call({:show, shown}, _from, _state), do: {:reply, :ok, shown}
  def handle_call(:shown, _from, state), do: {:reply, state, state}
end
