defmodule Simulator.Agents.ShipAgent.PlanStep do
  @moduledoc """
  A single step within a ship's plan.

  Steps are executed sequentially. Each step has an action type and
  associated parameters (commodity, quantity, destination, etc.).
  """

  @type t :: %__MODULE__{
          action: :travel | :buy | :sell | :refuel | :idle | :dock | :undock,
          to: String.t() | nil,
          commodity: atom() | nil,
          quantity: non_neg_integer() | nil,
          at: String.t() | nil
        }

  @enforce_keys [:action]
  defstruct [:action, :to, :commodity, :quantity, :at]
end
