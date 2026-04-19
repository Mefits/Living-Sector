defmodule Simulator.Spatial.Quadtree do
  @moduledoc """
  Pure functional quadtree for 2D spatial indexing.

  Divides 2D space into hierarchical cells for efficient spatial queries.
  Entities are `{id, x, y}` tuples stored in leaf nodes. When a leaf
  exceeds `bucket_size`, it splits into four children (NW, NE, SW, SE).
  When children collapse below `bucket_size`, they merge back into a leaf.

  No processes or ETS — this is a pure data structure passed by value.
  The `Simulator.Spatial.ChunkManager` holds the quadtree in its state.

  ## Default Parameters

    * Bounds: `{-4.0, -4.0, 8.0, 8.0}` (matches the SVG viewBox)
    * Max depth: 6 (smallest cell = 0.125 units)
    * Bucket size: 8 (leaf splits when exceeded)

  ## Examples

      iex> qt = Quadtree.new({-4.0, -4.0, 8.0, 8.0})
      iex> qt = Quadtree.insert(qt, {"ship-1", 1.0, 0.5})
      iex> Quadtree.query_radius(qt, {1.0, 0.5}, 0.1)
      [{"ship-1", 1.0, 0.5}]
  """

  @type entity :: {id :: term(), x :: float(), y :: float()}
  @type bounds :: {x :: float(), y :: float(), w :: float(), h :: float()}
  @type t :: %__MODULE__{
          bounds: bounds(),
          depth: non_neg_integer(),
          max_depth: non_neg_integer(),
          bucket_size: pos_integer(),
          entities: [entity()],
          children: nil | {t(), t(), t(), t()}
        }

  @default_max_depth 6
  @default_bucket_size 8

  defstruct [
    :bounds,
    depth: 0,
    max_depth: @default_max_depth,
    bucket_size: @default_bucket_size,
    entities: [],
    children: nil
  ]

  @doc """
  Creates a new empty quadtree with the given bounds.

  Bounds are `{x, y, width, height}` where `(x, y)` is the top-left corner.

  ## Options

    * `:max_depth` — maximum subdivision depth (default: #{@default_max_depth})
    * `:bucket_size` — max entities per leaf before splitting (default: #{@default_bucket_size})
  """
  @spec new(bounds(), keyword()) :: t()
  def new(bounds, opts \\ []) do
    %__MODULE__{
      bounds: bounds,
      max_depth: Keyword.get(opts, :max_depth, @default_max_depth),
      bucket_size: Keyword.get(opts, :bucket_size, @default_bucket_size)
    }
  end

  @doc """
  Inserts an entity `{id, x, y}` into the quadtree.

  If the entity's position is outside the tree's bounds, it is silently ignored.
  """
  @spec insert(t(), entity()) :: t()
  def insert(%__MODULE__{} = tree, {_id, x, y} = entity) do
    if in_bounds?(tree.bounds, x, y) do
      do_insert(tree, entity)
    else
      tree
    end
  end

  @doc """
  Removes an entity by ID from the quadtree.
  """
  @spec remove(t(), term()) :: t()
  def remove(%__MODULE__{children: nil} = tree, id) do
    %{tree | entities: Enum.reject(tree.entities, fn {eid, _, _} -> eid == id end)}
  end

  def remove(%__MODULE__{children: {nw, ne, sw, se}} = tree, id) do
    children = {remove(nw, id), remove(ne, id), remove(sw, id), remove(se, id)}
    tree = %{tree | children: children}
    maybe_collapse(tree)
  end

  @doc """
  Updates an entity's position. Equivalent to remove + insert.
  """
  @spec update(t(), term(), {float(), float()}) :: t()
  def update(tree, id, {new_x, new_y}) do
    tree
    |> remove(id)
    |> insert({id, new_x, new_y})
  end

  @doc """
  Returns all entities within `radius` of the point `{cx, cy}`.
  """
  @spec query_radius(t(), {float(), float()}, float()) :: [entity()]
  def query_radius(%__MODULE__{} = tree, {cx, cy}, radius) do
    # First check if the query circle intersects this node's bounds
    if circle_intersects_bounds?(cx, cy, radius, tree.bounds) do
      do_query_radius(tree, cx, cy, radius * radius)
    else
      []
    end
  end

  @doc """
  Returns all entities within the rectangle `{rx, ry, rw, rh}`.
  """
  @spec query_rect(t(), bounds()) :: [entity()]
  def query_rect(%__MODULE__{} = tree, rect) do
    if bounds_intersect?(tree.bounds, rect) do
      do_query_rect(tree, rect)
    else
      []
    end
  end

  @doc """
  Returns all entities in the quadtree.
  """
  @spec all(t()) :: [entity()]
  def all(%__MODULE__{children: nil, entities: entities}), do: entities

  def all(%__MODULE__{children: {nw, ne, sw, se}}) do
    all(nw) ++ all(ne) ++ all(sw) ++ all(se)
  end

  @doc """
  Returns the total number of entities in the quadtree.
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{children: nil, entities: entities}), do: length(entities)

  def size(%__MODULE__{children: {nw, ne, sw, se}}) do
    size(nw) + size(ne) + size(sw) + size(se)
  end

  # --- Private: Insert ---

  defp do_insert(%__MODULE__{children: nil} = tree, entity) do
    entities = [entity | tree.entities]

    if length(entities) > tree.bucket_size and tree.depth < tree.max_depth do
      split(%{tree | entities: entities})
    else
      %{tree | entities: entities}
    end
  end

  defp do_insert(%__MODULE__{children: {nw, ne, sw, se}} = tree, {_id, x, y} = entity) do
    {mx, my} = midpoint(tree.bounds)

    children =
      cond do
        x <= mx and y <= my -> {do_insert(nw, entity), ne, sw, se}
        x > mx and y <= my -> {nw, do_insert(ne, entity), sw, se}
        x <= mx and y > my -> {nw, ne, do_insert(sw, entity), se}
        true -> {nw, ne, sw, do_insert(se, entity)}
      end

    %{tree | children: children}
  end

  # --- Private: Split & Collapse ---

  defp split(tree) do
    {x, y, w, h} = tree.bounds
    hw = w / 2
    hh = h / 2
    next_depth = tree.depth + 1

    base = %__MODULE__{
      depth: next_depth,
      max_depth: tree.max_depth,
      bucket_size: tree.bucket_size
    }

    nw = %{base | bounds: {x, y, hw, hh}}
    ne = %{base | bounds: {x + hw, y, hw, hh}}
    sw = %{base | bounds: {x, y + hh, hw, hh}}
    se = %{base | bounds: {x + hw, y + hh, hw, hh}}

    branch = %{tree | entities: [], children: {nw, ne, sw, se}}

    Enum.reduce(tree.entities, branch, fn entity, acc ->
      do_insert(acc, entity)
    end)
  end

  defp maybe_collapse(%__MODULE__{children: {nw, ne, sw, se}} = tree) do
    total = size(nw) + size(ne) + size(sw) + size(se)

    if total <= tree.bucket_size do
      %{tree | entities: all(nw) ++ all(ne) ++ all(sw) ++ all(se), children: nil}
    else
      tree
    end
  end

  # --- Private: Query helpers ---

  defp do_query_radius(%__MODULE__{children: nil, entities: entities}, cx, cy, radius_sq) do
    Enum.filter(entities, fn {_id, x, y} ->
      dx = x - cx
      dy = y - cy
      dx * dx + dy * dy <= radius_sq
    end)
  end

  defp do_query_radius(%__MODULE__{children: {nw, ne, sw, se}}, cx, cy, radius_sq) do
    do_query_radius(nw, cx, cy, radius_sq) ++
      do_query_radius(ne, cx, cy, radius_sq) ++
      do_query_radius(sw, cx, cy, radius_sq) ++
      do_query_radius(se, cx, cy, radius_sq)
  end

  defp do_query_rect(%__MODULE__{children: nil, entities: entities}, {rx, ry, rw, rh}) do
    Enum.filter(entities, fn {_id, x, y} ->
      x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
    end)
  end

  defp do_query_rect(%__MODULE__{children: {nw, ne, sw, se}}, rect) do
    collect = fn child ->
      if bounds_intersect?(child.bounds, rect), do: do_query_rect(child, rect), else: []
    end

    collect.(nw) ++ collect.(ne) ++ collect.(sw) ++ collect.(se)
  end

  # --- Private: Geometry ---

  defp in_bounds?({bx, by, bw, bh}, x, y) do
    x >= bx and x <= bx + bw and y >= by and y <= by + bh
  end

  defp midpoint({x, y, w, h}), do: {x + w / 2, y + h / 2}

  defp circle_intersects_bounds?(cx, cy, radius, {bx, by, bw, bh}) do
    # Find closest point on the AABB to the circle center
    closest_x = max(bx, min(cx, bx + bw))
    closest_y = max(by, min(cy, by + bh))
    dx = cx - closest_x
    dy = cy - closest_y
    dx * dx + dy * dy <= radius * radius
  end

  defp bounds_intersect?({ax, ay, aw, ah}, {bx, by, bw, bh}) do
    ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
  end
end
