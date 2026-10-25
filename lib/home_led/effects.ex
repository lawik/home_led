defmodule HomeLed.Effects do
  @moduledoc """
  The effects the strip knows. `:solid` is no effect: the chosen colour on every pixel.
  The rest are `HomeLed.Effect` modules. Names are what Home Assistant shows in the
  effect select.
  """

  @effects [HomeLed.Effects.Flicker, HomeLed.Effects.Breathe, HomeLed.Effects.Rainbow]
  @solid_name "Solid"

  @type effect :: :solid | module()

  @doc "Every effect, as `{name, effect}`, solid first."
  @spec all() :: [{String.t(), effect()}]
  def all, do: [{@solid_name, :solid} | Enum.map(@effects, &{&1.name(), &1})]

  @doc "The names, in the order the select shows them."
  @spec names() :: [String.t()]
  def names, do: Enum.map(all(), &elem(&1, 0))

  @doc "The effect a select option names."
  @spec from_name(String.t()) :: {:ok, effect()} | :error
  def from_name(name) do
    case List.keyfind(all(), name, 0) do
      {_, effect} -> {:ok, effect}
      nil -> :error
    end
  end

  @doc "The select option for an effect."
  @spec name(effect()) :: String.t()
  def name(:solid), do: @solid_name
  def name(module), do: module.name()

  @doc "Whether `effect` is one of ours."
  @spec valid?(term()) :: boolean()
  def valid?(effect), do: effect == :solid or effect in @effects
end
