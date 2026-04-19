defmodule Simulator.Spatial.Observer do
  @moduledoc """
  A point in space that activates nearby chunks to full tick rate.

  Observers create a gradient around themselves: chunks inside the
  activation radius tick at divisor 1 (every tick), chunks beyond it
  tick at increasing divisors based on distance. There is no dormant
  state — even the farthest chunks still tick, just less often.

  ## Observer Types

    * `:dashboard` — debug observer, draggable on the SVG map
    * `:player` — future player viewport in Godot
    * `:system` — system-level observer (e.g., always-active narrative events)
  """

  @type t :: %__MODULE__{
          id: String.t(),
          x: float(),
          y: float(),
          radius: float(),
          owner: :dashboard | :player | :system,
          label: String.t() | nil
        }

  @enforce_keys [:id, :x, :y, :radius]
  defstruct [:id, :x, :y, :label, radius: 20.0, owner: :dashboard]
end
