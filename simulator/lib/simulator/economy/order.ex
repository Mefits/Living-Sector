defmodule Simulator.Economy.Order do
  @moduledoc """
  A buy or sell order placed on a market by an agent.

  Orders are collected by `Simulator.Agents.MarketAgent` each tick and
  matched via `Simulator.Economy.OrderBook`. Unmatched orders expire
  after a configurable number of ticks.
  """

  @type t :: %__MODULE__{
          id: integer(),
          agent_id: String.t(),
          type: :buy | :sell,
          commodity: Simulator.Economy.Commodities.commodity(),
          quantity: pos_integer(),
          price: float(),
          placed_at_tick: non_neg_integer(),
          expiry_tick: non_neg_integer() | nil
        }

  @enforce_keys [:id, :agent_id, :type, :commodity, :quantity, :price, :placed_at_tick]
  defstruct [:id, :agent_id, :type, :commodity, :quantity, :price, :placed_at_tick, :expiry_tick]

  @doc """
  Creates a new order with an auto-generated unique ID.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct!(__MODULE__, Map.put(attrs, :id, :erlang.unique_integer([:positive, :monotonic])))
  end
end
