defmodule Simulator.World.Location do
  @moduledoc """
  A spatial anchor in the simulation — a planet, orbital station, asteroid belt,
  or point in transit.

  Locations form the nodes of a graph that agents traverse. Each location is
  associated with a celestial body and may host one or more facilities.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          type: :planet | :moon | :station | :belt | :hub,
          body_id: String.t()
        }

  @enforce_keys [:id, :name, :type, :body_id]
  defstruct [:id, :name, :type, :body_id]
end
