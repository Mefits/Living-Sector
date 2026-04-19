defmodule Simulator.World.Body do
  @moduledoc """
  A celestial body with simplified orbital parameters.

  Bodies orbit their star at a fixed radius, advancing their angle each
  tick. The `SystemAgent` uses body positions to calculate dynamic travel
  times between locations.
  """

  @type biome ::
          :terrestrial
          | :ocean
          | :desert
          | :ice_moon
          | :lifeless_moon
          | :asteroid
          | :gas_giant
          | :molten
          | :industrial
          | nil

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          type: :planet | :moon | :belt,
          orbit_radius: float(),
          orbit_period: integer(),
          current_angle: float(),
          resources: %{atom() => float()},
          biome: biome()
        }

  @enforce_keys [:id, :name, :type, :orbit_radius, :orbit_period]
  defstruct [
    :id,
    :name,
    :type,
    :orbit_radius,
    :orbit_period,
    :biome,
    current_angle: 0.0,
    resources: %{}
  ]

  @doc """
  Advances the body's orbital position by one tick.
  """
  @spec advance_orbit(t()) :: t()
  def advance_orbit(%__MODULE__{} = body) do
    # Scale orbital advance by tick_scale so orbits match wall-clock time
    delta = 360.0 / body.orbit_period * Simulator.Simulation.Config.tick_scale()
    new_angle = :math.fmod(body.current_angle + delta, 360.0)
    %{body | current_angle: new_angle}
  end

  @doc """
  Calculates the 2D distance between two bodies based on their current
  orbital positions. Uses simplified circular orbit geometry.
  """
  @spec distance(t(), t()) :: float()
  def distance(a, b) do
    ax = a.orbit_radius * :math.cos(a.current_angle * :math.pi() / 180)
    ay = a.orbit_radius * :math.sin(a.current_angle * :math.pi() / 180)
    bx = b.orbit_radius * :math.cos(b.current_angle * :math.pi() / 180)
    by = b.orbit_radius * :math.sin(b.current_angle * :math.pi() / 180)

    :math.sqrt(:math.pow(bx - ax, 2) + :math.pow(by - ay, 2))
  end
end
