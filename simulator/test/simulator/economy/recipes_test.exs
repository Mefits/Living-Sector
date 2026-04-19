defmodule Simulator.Economy.RecipesTest do
  use ExUnit.Case, async: true

  alias Simulator.Economy.Recipes

  describe "for_facility_type/1" do
    test "returns refinery recipes" do
      recipes = Recipes.for_facility_type(:refinery)
      assert length(recipes) == 4
      assert Enum.all?(recipes, &(&1.facility_type == :refinery))
    end

    test "returns factory recipes" do
      recipes = Recipes.for_facility_type(:factory)
      assert length(recipes) >= 4
      assert Enum.all?(recipes, &(&1.facility_type == :factory))
    end

    test "returns farm recipes" do
      recipes = Recipes.for_facility_type(:farm)
      assert length(recipes) == 1
      assert hd(recipes).id == :grow_food
    end

    test "returns empty for stations" do
      assert Recipes.for_facility_type(:station) == []
    end
  end

  describe "execute/3" do
    test "smelting ore into metals" do
      recipe = Recipes.get(:smelt_metals)
      supply = %{ore: 100, fuel: 20}

      {new_supply, produced} = Recipes.execute(recipe, supply, 1.0, 1)

      assert produced.metals == 8
      assert new_supply.ore == 90
      assert new_supply.fuel == 19
      assert new_supply.metals == 8
    end

    test "partial production when input is scarce" do
      recipe = Recipes.get(:smelt_metals)
      # Only 5 ore (need 10), but plenty of fuel
      supply = %{ore: 5, fuel: 20}

      {new_supply, produced} = Recipes.execute(recipe, supply, 1.0, 1)

      # Scale = 5/10 = 0.5 → outputs halved
      assert produced.metals == 4
      assert new_supply.ore == 0
    end

    test "no production when input missing" do
      recipe = Recipes.get(:smelt_metals)
      supply = %{ore: 0, fuel: 20}

      {new_supply, produced} = Recipes.execute(recipe, supply)

      assert produced == %{}
      assert new_supply.ore == 0
      assert new_supply.fuel == 20
    end

    test "processing ice produces water and fuel" do
      recipe = Recipes.get(:process_ice)
      supply = %{ice: 80}

      {new_supply, produced} = Recipes.execute(recipe, supply, 1.0, 1)

      assert produced.water == 6
      assert produced.fuel == 5
      assert new_supply.ice == 72
    end

    test "efficiency scales output" do
      recipe = Recipes.get(:smelt_metals)
      supply = %{ore: 100, fuel: 100}

      {_supply_full, full} = Recipes.execute(recipe, supply, 1.0, 1)
      {_supply_half, half} = Recipes.execute(recipe, supply, 0.5, 1)

      assert full.metals > half.metals
    end

    test "growing food from water" do
      recipe = Recipes.get(:grow_food)
      supply = %{water: 30}

      {new_supply, produced} = Recipes.execute(recipe, supply, 1.0, 1)

      assert produced.food == 10
      assert new_supply.water == 27
    end
  end

  describe "commodity tiers" do
    test "all commodities have base prices" do
      for commodity <- Simulator.Economy.Commodities.all() do
        assert Simulator.Economy.Commodities.base_price(commodity) > 0,
               "#{commodity} has no base price"
      end
    end

    test "refined costs more than raw on average" do
      raw_avg =
        Simulator.Economy.Commodities.by_tier(:raw)
        |> Enum.map(&Simulator.Economy.Commodities.base_price/1)
        |> Enum.sum()
        |> Kernel./(3)

      refined_avg =
        Simulator.Economy.Commodities.by_tier(:refined)
        |> Enum.map(&Simulator.Economy.Commodities.base_price/1)
        |> Enum.sum()
        |> Kernel./(4)

      assert refined_avg > raw_avg
    end

    test "manufactured costs more than refined on average" do
      refined_avg =
        Simulator.Economy.Commodities.by_tier(:refined)
        |> Enum.map(&Simulator.Economy.Commodities.base_price/1)
        |> Enum.sum()
        |> Kernel./(4)

      manufactured_avg =
        Simulator.Economy.Commodities.by_tier(:manufactured)
        |> Enum.map(&Simulator.Economy.Commodities.base_price/1)
        |> Enum.sum()
        |> Kernel./(3)

      assert manufactured_avg > refined_avg
    end
  end
end
