defmodule Zipfelfolio.MarketData.DivvyDiary.Response do
  @moduledoc """
  Reads DivvyDiary's answer for one ISIN (`GET /symbols/{isin}`). DivvyDiary does not document it;
  the format is assumed from a recorded answer in Portfolio Performance's tests
  (`divvy_diary_response_with_payments.json`):

  - `countryWeightings` and `sectorWeightings` are lists of `{"country": "US", "weight": 0.19}` and
    `{"sector": "Energy", "weight": 0.13}`; a map such as `{"US": 0.19}` is read too
  - countries are ISO 3166 alpha-2 codes, sectors GICS names in English
  - weights are fractions of 1, and the scale does not matter, see `Zipfelfolio.Allocation`
  - a share has empty lists, and its own `country` and `sector`, which are not read
  """

  @doc """
  The composition as `%{countries: %{code => weight}, sectors: %{name => weight}}`; null counts as
  no weights, and a country or sector listed twice adds up.
  """
  def composition(%{"countryWeightings" => countries, "sectorWeightings" => sectors}) do
    with {:ok, countries} <- weights(countries, "country"),
         {:ok, sectors} <- weights(sectors, "sector") do
      {:ok, %{countries: countries, sectors: sectors}}
    end
  end

  def composition(_json), do: {:error, :invalid_response}

  defp weights(nil, _key), do: {:ok, %{}}
  defp weights(map, _key) when is_map(map), do: sum(Map.to_list(map))

  defp weights(list, key) when is_list(list), do: list |> Enum.map(&pair(&1, key)) |> sum()
  defp weights(_other, _key), do: {:error, :invalid_response}

  defp pair(%{"weight" => weight} = item, key), do: {item[key], weight}
  defp pair(_item, _key), do: :invalid

  defp sum(pairs) do
    if Enum.all?(pairs, &match?({name, weight} when is_binary(name) and is_number(weight), &1)),
      do:
        {:ok,
         Enum.reduce(pairs, %{}, fn {name, w}, acc -> Map.update(acc, name, w, &(&1 + w)) end)},
      else: {:error, :invalid_response}
  end
end
