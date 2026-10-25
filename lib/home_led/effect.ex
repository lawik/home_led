defmodule HomeLed.Effect do
  @moduledoc """
  An animation for the strip. `HomeLed.Scene` runs the selected effect at its `fps/0`,
  asking for one RGB frame per tick (three bytes per pixel, in wire order).

  The context an effect gets:

    * `count` - pixels in the strip
    * `color` - the colour Home Assistant chose, as `{r, g, b}` bytes with the brightness
      already applied; what a solid light would show
    * `brightness` - `0.0..1.0`, for effects that make their own colours
    * `time_ms` - milliseconds since the effect started

  `init/1` builds per-run state (random seeds, per-pixel levels) and runs again when the
  LED count changes.
  """

  @type context :: %{
          count: pos_integer(),
          color: HomeLed.Color.rgb(),
          brightness: float(),
          time_ms: non_neg_integer()
        }

  @callback name() :: String.t()
  @callback fps() :: pos_integer()
  @callback init(context()) :: term()
  @callback frame(term(), context()) :: {binary(), term()}
end
