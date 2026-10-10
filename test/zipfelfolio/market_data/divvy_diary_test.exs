defmodule Zipfelfolio.MarketData.DivvyDiaryTest do
  use ExUnit.Case, async: false

  alias Zipfelfolio.MarketData.DivvyDiary
  alias Zipfelfolio.MarketData.DivvyDiary.Response

  # Written by hand: the format is assumed, see the moduledoc of `Response`.
  @json "test/fixtures/divvydiary/symbol.json" |> File.read!() |> JSON.decode!()

  describe "Response.composition/1" do
    test "reads the weights per country and per sector" do
      assert {:ok, %{countries: countries, sectors: sectors}} = Response.composition(@json)

      assert countries == %{
               "US" => 0.5,
               "JP" => 0.1,
               "GB" => 0.1,
               "CA" => 0.05,
               "AU" => 0.05,
               "CN" => 0.1,
               "BR" => 0.1
             }

      assert map_size(sectors) == 7
      assert sectors["Information Technology"] == 0.25
    end

    test "reads weights given as a map, and adds up a country listed twice" do
      json = %{
        "countryWeightings" => [
          %{"country" => "US", "weight" => 0.5},
          %{"country" => "US", "weight" => 0.25},
          %{"country" => "JP", "weight" => 0.25}
        ],
        "sectorWeightings" => %{"Energy" => 1}
      }

      assert Response.composition(json) ==
               {:ok, %{countries: %{"US" => 0.75, "JP" => 0.25}, sectors: %{"Energy" => 1}}}
    end

    test "a share without weightings has no composition" do
      json = %{
        "country" => "DE",
        "sector" => "Health Care",
        "countryWeightings" => [],
        "sectorWeightings" => nil
      }

      assert Response.composition(json) == {:ok, %{countries: %{}, sectors: %{}}}
    end

    test "an answer of another shape is invalid, so the stored composition stays" do
      for json <- [
            %{"countries" => [], "sectors" => []},
            Map.put(@json, "countryWeightings", [%{"name" => "US", "weight" => 1}]),
            Map.put(@json, "countryWeightings", [%{"country" => "US", "weight" => "1"}]),
            Map.put(@json, "sectorWeightings", ["Energy"]),
            Map.put(@json, "sectorWeightings", "mixed"),
            []
          ] do
        assert Response.composition(json) == {:error, :invalid_response}
      end
    end
  end

  describe "available?/0" do
    setup do
      config = Application.get_env(:zipfelfolio, DivvyDiary)
      on_exit(fn -> Application.put_env(:zipfelfolio, DivvyDiary, config || []) end)
    end

    test "only with an API key" do
      Application.put_env(:zipfelfolio, DivvyDiary, api_key: nil)
      refute DivvyDiary.available?()

      Application.put_env(:zipfelfolio, DivvyDiary, api_key: "")
      refute DivvyDiary.available?()

      Application.put_env(:zipfelfolio, DivvyDiary, api_key: "key")
      assert DivvyDiary.available?()
    end
  end
end
