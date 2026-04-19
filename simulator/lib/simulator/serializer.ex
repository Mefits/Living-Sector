defmodule Simulator.Serializer do
  @moduledoc """
  Converts simulation data to JSON-safe maps for Channel and API consumers.

  PubSub events use atom keys and Elixir-native types. External clients
  need string keys and no structs. This module provides a single conversion
  point used by Channels (and any future REST API).

  ## Examples

      iex> Serializer.serialize_event(:price_update, %{ore: 42.0, fuel: 25.0})
      %{"ore" => 42.0, "fuel" => 25.0}

      iex> Serializer.serialize_state(%{id: "ship-1", cargo: %{ore: 100}})
      %{"id" => "ship-1", "cargo" => %{"ore" => 100}}
  """

  @doc """
  Converts a PubSub event payload to a JSON-safe map.
  """
  @spec serialize_event(atom(), map()) :: map()
  def serialize_event(event_name, payload) do
    payload
    |> deep_stringify()
    |> Map.put("event", to_string(event_name))
  end

  @doc """
  Converts an agent state map to a JSON-safe map.

  Strips internal keys (prefixed with `__`) and converts all atom keys
  to strings recursively.
  """
  @spec serialize_state(map()) :: map()
  def serialize_state(state) when is_map(state) do
    state
    |> strip_internal_keys()
    |> simplify_complex_fields()
    |> deep_stringify()
  end

  @doc """
  Deep-converts a map/value to JSON-safe format: atom keys become strings,
  structs become plain maps, tuples become lists.
  """
  @spec deep_stringify(term()) :: term()
  def deep_stringify(%{__struct__: _} = struct) do
    struct |> Map.from_struct() |> deep_stringify()
  end

  def deep_stringify(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), deep_stringify(v)} end)
  end

  def deep_stringify(list) when is_list(list) do
    Enum.map(list, &deep_stringify/1)
  end

  def deep_stringify(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> deep_stringify()
  end

  def deep_stringify(atom) when is_atom(atom) and not is_boolean(atom) and not is_nil(atom) do
    to_string(atom)
  end

  def deep_stringify(pid) when is_pid(pid), do: inspect(pid)

  def deep_stringify(ref) when is_reference(ref), do: inspect(ref)

  def deep_stringify(fun) when is_function(fun), do: "function"

  def deep_stringify(value), do: value

  # Replace un-serializable fields with safe summaries
  defp simplify_complex_fields(map) do
    map
    |> Map.update(:current_bt, nil, fn
      nil -> nil
      bt -> Simulator.AI.BehaviorTree.current_action(bt) |> to_string()
    end)
    |> Map.update(:personality, nil, fn
      nil ->
        nil

      p when is_map(p) ->
        Map.new(p, fn {k, v} -> {k, if(is_float(v), do: Float.round(v, 2), else: v)} end)

      p ->
        p
    end)
    |> Map.update(:position, nil, fn
      {x, y} -> %{x: Float.round(x * 1.0, 4), y: Float.round(y * 1.0, 4)}
      other -> other
    end)
    |> Map.update(:available_contracts, nil, fn
      nil ->
        nil

      contracts when is_list(contracts) ->
        Enum.map(contracts, fn c ->
          Map.take(c, [
            :id,
            :commodity,
            :quantity,
            :payment,
            :status,
            :source_location,
            :destination_location,
            :delivery_fee,
            :cargo_deposit,
            :distance
          ])
        end)

      c ->
        c
    end)
    |> Map.update(:active_contract, nil, fn
      nil ->
        nil

      c when is_map(c) ->
        Map.take(c, [
          :id,
          :commodity,
          :quantity,
          :payment,
          :status,
          :source_location,
          :destination_location,
          :delivery_fee,
          :cargo_deposit,
          :reserve_id
        ])

      c ->
        c
    end)
  end

  defp strip_internal_keys(map) do
    Map.reject(map, fn {k, _v} ->
      key_str = to_string(k)
      String.starts_with?(key_str, "__")
    end)
  end
end
