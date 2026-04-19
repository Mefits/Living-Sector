defmodule Simulator.Spatial.ShipMetadata do
  @moduledoc """
  ETS-backed lightweight ship state with delta tracking.

  Ships call `put/2` whenever their state-relevant fields might have
  changed. The module diffs against the last stored value and marks
  the ship as dirty only if anything actually changed.

  TickCoordinator periodically calls `flush_dirty/0` to get the set of
  changed ships for the `simulation:ship_states` broadcast — only pushing
  deltas instead of every ship every tick.

  Three tables:
    * `:ship_metadata` — `{ship_id, metadata}` — current state
    * `:ship_metadata_dirty` — `{ship_id}` — changed since last flush
  """

  @ets_table :ship_metadata
  @dirty_table :ship_metadata_dirty

  @doc """
  Initializes the ETS tables. Called by Application on startup.
  """
  @spec init() :: :ok
  def init do
    if :ets.whereis(@ets_table) == :undefined do
      :ets.new(@ets_table, [
        :named_table,
        :set,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])
    end

    if :ets.whereis(@dirty_table) == :undefined do
      :ets.new(@dirty_table, [
        :named_table,
        :set,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])
    end

    :ok
  end

  @doc """
  Updates a ship's metadata. If different from existing, marks dirty.
  """
  @spec put(String.t(), map()) :: :ok
  def put(ship_id, metadata) when is_binary(ship_id) and is_map(metadata) do
    case :ets.lookup(@ets_table, ship_id) do
      [{_, ^metadata}] ->
        # No change — skip
        :ok

      _ ->
        :ets.insert(@ets_table, {ship_id, metadata})
        :ets.insert(@dirty_table, {ship_id})
        :ok
    end
  end

  @doc """
  Returns metadata for a single ship.
  """
  @spec get(String.t()) :: map() | nil
  def get(ship_id) do
    case :ets.lookup(@ets_table, ship_id) do
      [{_, meta}] -> meta
      _ -> nil
    end
  end

  @doc """
  Returns all ship metadata as a map keyed by ship_id.
  """
  @spec all() :: %{String.t() => map()}
  def all do
    case :ets.whereis(@ets_table) do
      :undefined ->
        %{}

      _ ->
        :ets.tab2list(@ets_table)
        |> Map.new()
    end
  end

  @doc """
  Returns and clears the dirty set — ship_ids whose metadata changed
  since the last flush. Each entry pairs the id with current metadata.
  Used by TickCoordinator for the ship_states delta broadcast.
  """
  @spec flush_dirty() :: [{String.t(), map()}]
  def flush_dirty do
    case :ets.whereis(@dirty_table) do
      :undefined ->
        []

      _ ->
        dirty_ids = :ets.tab2list(@dirty_table) |> Enum.map(&elem(&1, 0))
        :ets.delete_all_objects(@dirty_table)

        Enum.flat_map(dirty_ids, fn id ->
          case :ets.lookup(@ets_table, id) do
            [{_, meta}] -> [{id, meta}]
            _ -> []
          end
        end)
    end
  end

  @doc """
  Removes a ship's metadata.
  """
  @spec delete(String.t()) :: :ok
  def delete(ship_id) do
    :ets.delete(@ets_table, ship_id)
    :ets.delete(@dirty_table, ship_id)
    :ok
  end
end
