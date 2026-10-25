defmodule HomeLed.SpiEncoderTest do
  use ExUnit.Case, async: true

  alias HomeLed.SpiEncoder

  test "each data bit becomes a 4-bit symbol, then a reset tail" do
    # 0b10100000: 1 -> 0xE, 0 -> 0x8
    assert <<0xE8, 0xE8, 0x88, 0x88, tail::binary>> = SpiEncoder.encode(<<0b10100000>>)
    assert tail == :binary.copy(<<0>>, 60)
    assert byte_size(SpiEncoder.encode(<<1, 2, 3>>)) == SpiEncoder.encoded_size(3)
    assert <<0xEE, 0xEE, 0xEE, 0xEE, _::binary>> = SpiEncoder.encode(<<0xFF>>)
    assert <<0x88, 0x88, 0x88, 0x88, _::binary>> = SpiEncoder.encode(<<0x00>>)
  end
end
