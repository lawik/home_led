defmodule HomeLed.SpiEncoder do
  @moduledoc """
  Encodes raw LED bytes into the SPI bit pattern that WS281x LEDs expect when
  clocked at 3.2 MHz, the same raw SPI format Fledex uses.

  Each data bit becomes a 4-bit SPI symbol, `1110` for a one and `1000` for a
  zero, so every input byte becomes 4 SPI bytes. The encodings of all 256 byte
  values are computed at compile time, so encoding is one lookup per byte.
  """
  import Bitwise

  # Zero bytes after the frame hold the line low long enough for the LEDs to latch.
  @reset_tail :binary.copy(<<0x00>>, 60)

  @spi_table (for byte <- 0..255 do
                for shift <- 7..0//-1, into: <<>> do
                  if (byte >>> shift &&& 1) == 1, do: <<0xE::4>>, else: <<0x8::4>>
                end
              end)
             |> List.to_tuple()

  @doc "Encodes a frame of LED bytes into an SPI buffer ready to transfer, reset tail included."
  @spec encode(binary()) :: binary()
  def encode(frame) when is_binary(frame) do
    encoded = for <<byte <- frame>>, into: <<>>, do: elem(@spi_table, byte)
    <<encoded::binary, @reset_tail::binary>>
  end

  @doc "How many bytes `encode/1` produces for a frame of `bytes` LED bytes."
  @spec encoded_size(non_neg_integer()) :: pos_integer()
  def encoded_size(bytes), do: bytes * 4 + byte_size(@reset_tail)
end
