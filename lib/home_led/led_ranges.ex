defmodule HomeLed.LedRanges do
  @moduledoc """
  Ranges of LEDs, as typed into Home Assistant: `"5"`, `"3-8"` or `"3-8, 10-200"`.
  Pixels are numbered from 1, so `"1"` is the first LED on the strip. Ranges are
  separated by commas, semicolons or whitespace; a range is a single number or
  `from-to`, both ends included.

  Parsing validates: every number is 1 or more, `from` is not after `to`, and no two
  ranges overlap (`"3-8, 5"` is rejected; `"3-5, 6-8"` is fine). Ranges past the end of
  the strip are allowed and just do nothing until the LED count catches up with them.

  Used for the LEDs the strip leaves dark (`HomeLed.Settings.disabled_ranges/0`):
  `blank/2` zeroes those pixels in an RGB frame.
  """

  @typedoc "An inclusive range of 1-indexed LED positions."
  @type range :: {pos_integer(), pos_integer()}
  @type ranges :: [range()]

  @separators ~r/[,;\s]+/
  @range ~r/^(\d+)(?:-(\d+))?$/

  @doc """
  Parse a ranges string into sorted `{from, to}` tuples. An empty string is no ranges.

      iex> HomeLed.LedRanges.parse("10-200, 1 3-8")
      {:ok, [{1, 1}, {3, 8}, {10, 200}]}
      iex> HomeLed.LedRanges.parse("3-8, 5")
      {:error, "ranges 3-8 and 5 overlap"}
      iex> HomeLed.LedRanges.parse("8-3")
      {:error, "8-3 is backwards"}
      iex> HomeLed.LedRanges.parse("")
      {:ok, []}
  """
  @spec parse(String.t()) :: {:ok, ranges()} | {:error, String.t()}
  def parse(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.split(@separators, trim: true)
    |> Enum.reduce_while({:ok, []}, fn token, {:ok, acc} ->
      case parse_range(token) do
        {:ok, range} -> {:cont, {:ok, [range | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, ranges} -> ranges |> Enum.sort() |> check_overlap()
      error -> error
    end
  end

  @doc """
  Parse, raising on invalid input. Lists of `{from, to}` tuples are validated as-is.
  """
  @spec parse!(String.t() | ranges()) :: ranges()
  def parse!(text) when is_binary(text) do
    case parse(text) do
      {:ok, ranges} -> ranges
      {:error, reason} -> raise ArgumentError, "invalid LED ranges #{inspect(text)}: #{reason}"
    end
  end

  def parse!(ranges) when is_list(ranges), do: ranges |> format() |> parse!()

  @doc """
  The string for ranges, as `parse/1` accepts it.

      iex> HomeLed.LedRanges.format([{3, 8}, {5, 5}, {10, 200}])
      "3-8, 5, 10-200"
      iex> HomeLed.LedRanges.format([])
      ""
  """
  @spec format(ranges()) :: String.t()
  def format(ranges) when is_list(ranges) do
    Enum.map_join(ranges, ", ", fn
      {n, n} -> Integer.to_string(n)
      {from, to} -> "#{from}-#{to}"
    end)
  end

  @doc "Whether `ranges` is a well-formed, non-overlapping list of `{from, to}` tuples."
  @spec valid?(term()) :: boolean()
  def valid?(ranges) when is_list(ranges) do
    Enum.all?(ranges, fn
      {from, to} -> is_integer(from) and is_integer(to) and from >= 1 and from <= to
      _ -> false
    end) and match?({:ok, _}, ranges |> Enum.sort() |> check_overlap())
  end

  def valid?(_), do: false

  @doc """
  Zero the pixels in `ranges` of an RGB frame (`bytes_per_led` bytes per pixel, 3 by
  default). Ranges past the end of the frame are clipped.

      iex> HomeLed.LedRanges.blank(<<1, 2, 3, 4, 5, 6, 7, 8, 9>>, [{2, 2}])
      <<1, 2, 3, 0, 0, 0, 7, 8, 9>>
      iex> HomeLed.LedRanges.blank(<<1, 2, 3, 4, 5, 6>>, [{2, 10}])
      <<1, 2, 3, 0, 0, 0>>
  """
  @spec blank(binary(), ranges(), pos_integer()) :: binary()
  def blank(frame, ranges, bytes_per_led \\ 3)

  def blank(frame, [], _bytes_per_led), do: frame

  def blank(frame, ranges, bytes_per_led) when is_binary(frame) do
    count = div(byte_size(frame), bytes_per_led)

    Enum.reduce(ranges, frame, fn {from, to}, acc ->
      from = max(from, 1)
      to = min(to, count)

      if from > to do
        acc
      else
        start = (from - 1) * bytes_per_led
        len = (to - from + 1) * bytes_per_led
        <<head::binary-size(^start), _::binary-size(^len), tail::binary>> = acc
        <<head::binary, 0::size(len)-unit(8), tail::binary>>
      end
    end)
  end

  defp parse_range(token) do
    case Regex.run(@range, token) do
      [_, from] -> single(from, token)
      [_, from, to] -> pair(String.to_integer(from), String.to_integer(to), token)
      nil -> {:error, "#{token} is not a number or a from-to range"}
    end
  end

  defp single(from, token), do: pair(String.to_integer(from), String.to_integer(from), token)

  defp pair(from, to, token) do
    cond do
      from < 1 or to < 1 -> {:error, "#{token}: LEDs are numbered from 1"}
      from > to -> {:error, "#{token} is backwards"}
      true -> {:ok, {from, to}}
    end
  end

  # sorted by `from`: each range must start after the previous one ends
  defp check_overlap(sorted) do
    sorted
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find(fn [{_, prev_to}, {from, _}] -> from <= prev_to end)
    |> case do
      nil -> {:ok, sorted}
      [a, b] -> {:error, "ranges #{format([a])} and #{format([b])} overlap"}
    end
  end
end
