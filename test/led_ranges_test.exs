defmodule HomeLed.LedRangesTest do
  use ExUnit.Case, async: true
  doctest HomeLed.LedRanges

  alias HomeLed.LedRanges

  test "parses singles and ranges with any of the separators" do
    assert LedRanges.parse("5") == {:ok, [{5, 5}]}
    assert LedRanges.parse("3-8") == {:ok, [{3, 8}]}
    assert LedRanges.parse("3-8,10-200") == {:ok, [{3, 8}, {10, 200}]}
    assert LedRanges.parse("3-8; 10-200") == {:ok, [{3, 8}, {10, 200}]}
    assert LedRanges.parse(" 3-8 \t10-200\n1 ") == {:ok, [{1, 1}, {3, 8}, {10, 200}]}
    assert LedRanges.parse("3-5, 6-8") == {:ok, [{3, 5}, {6, 8}]}
    assert LedRanges.parse("   ") == {:ok, []}
  end

  test "rejects garbage, zero, backwards and overlapping ranges" do
    assert {:error, "x is not a number or a from-to range"} = LedRanges.parse("x")
    assert {:error, "1-2-3 is not a number or a from-to range"} = LedRanges.parse("1-2-3")
    assert {:error, "0: LEDs are numbered from 1"} = LedRanges.parse("0")
    assert {:error, "0-4: LEDs are numbered from 1"} = LedRanges.parse("0-4")
    assert {:error, "8-3 is backwards"} = LedRanges.parse("8-3")
    assert {:error, "ranges 3-8 and 5 overlap"} = LedRanges.parse("5, 3-8")
    assert {:error, "ranges 3-8 and 8-10 overlap"} = LedRanges.parse("3-8, 8-10")
    assert {:error, "ranges 4 and 4 overlap"} = LedRanges.parse("4 4")
    assert_raise ArgumentError, ~r/overlap/, fn -> LedRanges.parse!("3-8, 5") end
  end

  test "format round-trips" do
    for text <- ["", "5", "3-8", "3-8, 10-200", "1, 3-5, 9"] do
      assert {:ok, ranges} = LedRanges.parse(text)
      assert LedRanges.format(ranges) == text
    end
  end

  test "valid? checks tuples and overlap" do
    assert LedRanges.valid?([])
    assert LedRanges.valid?([{10, 20}, {1, 1}])
    refute LedRanges.valid?([{0, 1}])
    refute LedRanges.valid?([{5, 3}])
    refute LedRanges.valid?([{1, 5}, {5, 6}])
    refute LedRanges.valid?([:nope])
    refute LedRanges.valid?("3-8")
  end

  test "blank zeroes pixels and clips to the frame" do
    frame = :binary.copy(<<9, 9, 9>>, 5)
    assert LedRanges.blank(frame, []) == frame
    assert LedRanges.blank(frame, [{1, 1}]) == <<0, 0, 0>> <> :binary.copy(<<9, 9, 9>>, 4)
    assert LedRanges.blank(frame, [{5, 5}]) == :binary.copy(<<9, 9, 9>>, 4) <> <<0, 0, 0>>

    assert LedRanges.blank(frame, [{2, 3}, {5, 9}]) ==
             <<9, 9, 9, 0, 0, 0, 0, 0, 0, 9, 9, 9, 0, 0, 0>>

    assert LedRanges.blank(frame, [{6, 9}]) == frame
    assert LedRanges.blank(<<1, 2, 3, 4, 5, 6, 7, 8>>, [{2, 2}], 4) == <<1, 2, 3, 4, 0, 0, 0, 0>>
  end
end
