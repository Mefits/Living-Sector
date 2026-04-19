defmodule Simulator.Spatial.QuadtreeTest do
  use ExUnit.Case, async: true

  alias Simulator.Spatial.Quadtree

  @bounds {-4.0, -4.0, 8.0, 8.0}

  describe "new/2" do
    test "creates an empty quadtree" do
      qt = Quadtree.new(@bounds)
      assert qt.bounds == @bounds
      assert qt.entities == []
      assert qt.children == nil
      assert Quadtree.size(qt) == 0
    end

    test "accepts custom options" do
      qt = Quadtree.new(@bounds, max_depth: 3, bucket_size: 4)
      assert qt.max_depth == 3
      assert qt.bucket_size == 4
    end
  end

  describe "insert/2" do
    test "inserts an entity into an empty tree" do
      qt = Quadtree.new(@bounds) |> Quadtree.insert({"ship-1", 1.0, 0.5})
      assert Quadtree.size(qt) == 1
      assert [{"ship-1", 1.0, 0.5}] = Quadtree.all(qt)
    end

    test "inserts multiple entities" do
      qt =
        Quadtree.new(@bounds)
        |> Quadtree.insert({"a", 0.0, 0.0})
        |> Quadtree.insert({"b", 1.0, 1.0})
        |> Quadtree.insert({"c", -2.0, -2.0})

      assert Quadtree.size(qt) == 3
    end

    test "ignores entities outside bounds" do
      qt = Quadtree.new(@bounds) |> Quadtree.insert({"out", 10.0, 10.0})
      assert Quadtree.size(qt) == 0
    end

    test "splits leaf when bucket overflows" do
      qt = Quadtree.new(@bounds, bucket_size: 2)

      qt =
        qt
        |> Quadtree.insert({"a", -1.0, -1.0})
        |> Quadtree.insert({"b", 1.0, 1.0})
        |> Quadtree.insert({"c", -1.0, 1.0})

      assert qt.children != nil
      assert Quadtree.size(qt) == 3
    end

    test "handles entities at the same position" do
      qt =
        Quadtree.new(@bounds)
        |> Quadtree.insert({"a", 0.0, 0.0})
        |> Quadtree.insert({"b", 0.0, 0.0})

      assert Quadtree.size(qt) == 2
    end

    test "inserts entity at boundary" do
      qt = Quadtree.new(@bounds) |> Quadtree.insert({"edge", -4.0, -4.0})
      assert Quadtree.size(qt) == 1
    end
  end

  describe "remove/2" do
    test "removes an entity by id" do
      qt =
        Quadtree.new(@bounds)
        |> Quadtree.insert({"a", 0.0, 0.0})
        |> Quadtree.insert({"b", 1.0, 1.0})
        |> Quadtree.remove("a")

      assert Quadtree.size(qt) == 1
      assert [{"b", 1.0, 1.0}] = Quadtree.all(qt)
    end

    test "removing nonexistent id is a no-op" do
      qt = Quadtree.new(@bounds) |> Quadtree.insert({"a", 0.0, 0.0})
      qt = Quadtree.remove(qt, "nonexistent")
      assert Quadtree.size(qt) == 1
    end

    test "collapses branch when entities fall below bucket_size" do
      qt = Quadtree.new(@bounds, bucket_size: 2)

      qt =
        qt
        |> Quadtree.insert({"a", -1.0, -1.0})
        |> Quadtree.insert({"b", 1.0, 1.0})
        |> Quadtree.insert({"c", -1.0, 1.0})

      assert qt.children != nil

      qt = Quadtree.remove(qt, "c")
      assert qt.children == nil
      assert Quadtree.size(qt) == 2
    end
  end

  describe "update/3" do
    test "moves an entity to a new position" do
      qt =
        Quadtree.new(@bounds)
        |> Quadtree.insert({"ship", 0.0, 0.0})
        |> Quadtree.update("ship", {2.0, 2.0})

      assert Quadtree.size(qt) == 1
      assert [{"ship", 2.0, 2.0}] = Quadtree.all(qt)
    end
  end

  describe "query_radius/3" do
    test "returns entities within radius" do
      qt =
        Quadtree.new(@bounds)
        |> Quadtree.insert({"near", 0.1, 0.1})
        |> Quadtree.insert({"far", 3.0, 3.0})

      results = Quadtree.query_radius(qt, {0.0, 0.0}, 0.5)
      assert length(results) == 1
      assert [{"near", 0.1, 0.1}] = results
    end

    test "returns empty list when nothing is in range" do
      qt = Quadtree.new(@bounds) |> Quadtree.insert({"a", 3.0, 3.0})
      assert [] = Quadtree.query_radius(qt, {-3.0, -3.0}, 0.5)
    end

    test "returns all when radius covers everything" do
      qt =
        Quadtree.new(@bounds)
        |> Quadtree.insert({"a", -3.0, -3.0})
        |> Quadtree.insert({"b", 3.0, 3.0})

      results = Quadtree.query_radius(qt, {0.0, 0.0}, 10.0)
      assert length(results) == 2
    end

    test "entity exactly on radius boundary is included" do
      qt = Quadtree.new(@bounds) |> Quadtree.insert({"edge", 1.0, 0.0})
      results = Quadtree.query_radius(qt, {0.0, 0.0}, 1.0)
      assert length(results) == 1
    end

    test "works with split trees" do
      qt = Quadtree.new(@bounds, bucket_size: 2)

      qt =
        qt
        |> Quadtree.insert({"a", -2.0, -2.0})
        |> Quadtree.insert({"b", 2.0, 2.0})
        |> Quadtree.insert({"c", -2.0, 2.0})
        |> Quadtree.insert({"d", 0.0, 0.0})

      results = Quadtree.query_radius(qt, {0.0, 0.0}, 1.0)
      assert [{"d", _, _}] = results
    end
  end

  describe "query_rect/2" do
    test "returns entities within rectangle" do
      qt =
        Quadtree.new(@bounds)
        |> Quadtree.insert({"in", 0.5, 0.5})
        |> Quadtree.insert({"out", 3.0, 3.0})

      results = Quadtree.query_rect(qt, {0.0, 0.0, 1.0, 1.0})
      assert [{"in", 0.5, 0.5}] = results
    end
  end

  describe "all/1 and size/1" do
    test "all returns every entity" do
      entities = for i <- 1..20, do: {"e#{i}", :rand.uniform() * 6 - 3, :rand.uniform() * 6 - 3}

      qt = Enum.reduce(entities, Quadtree.new(@bounds), &Quadtree.insert(&2, &1))

      assert Quadtree.size(qt) == 20
      all = Quadtree.all(qt)
      assert length(all) == 20

      ids = Enum.map(all, &elem(&1, 0)) |> MapSet.new()
      expected_ids = Enum.map(entities, &elem(&1, 0)) |> MapSet.new()
      assert ids == expected_ids
    end
  end
end
