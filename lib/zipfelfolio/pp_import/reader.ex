defmodule Zipfelfolio.PPImport.Reader do
  @moduledoc """
  Reads a PP file: a ZIP with `data.portfolio`, which is `PPPBV1` followed by a protobuf
  `PClient`. Field numbers follow PP's `client.proto`; only the fields zipfelfolio keeps are
  listed, all others are skipped. Messages become maps with atom keys.
  """

  alias Zipfelfolio.PPImport.Wire

  # {name, type} or {name, type, :repeated | :optional}. Absent optional fields are nil,
  # absent scalars take the proto3 default (0, false, first enum value).
  @messages %{
    client: %{
      1 => {:version, :int32},
      2 => {:securities, {:message, :security}, :repeated},
      3 => {:accounts, {:message, :account}, :repeated},
      4 => {:portfolios, {:message, :portfolio}, :repeated},
      5 => {:transactions, {:message, :transaction}, :repeated},
      6 => {:plans, {:message, :plan}, :repeated},
      8 => {:taxonomies, {:message, :taxonomy}, :repeated},
      11 => {:settings, {:message, :settings}, :optional},
      12 => {:base_currency, :string}
    },
    security: %{
      1 => {:uuid, :string},
      3 => {:name, :string},
      4 => {:currency, :string, :optional},
      6 => {:note, :string, :optional},
      7 => {:isin, :string, :optional},
      8 => {:ticker, :string, :optional},
      9 => {:wkn, :string, :optional},
      11 => {:feed, :string, :optional},
      13 => {:prices, {:message, :price}, :repeated},
      16 => {:latest, {:message, :price}, :optional},
      17 => {:attributes, :attributes},
      20 => {:retired, :bool}
    },
    price: %{1 => {:date, :epoch_day}, 2 => {:close, :int64}},
    account: %{
      1 => {:uuid, :string},
      2 => {:name, :string},
      3 => {:currency, :string},
      4 => {:note, :string, :optional},
      5 => {:retired, :bool},
      6 => {:attributes, :attributes}
    },
    portfolio: %{
      1 => {:uuid, :string},
      2 => {:name, :string},
      3 => {:note, :string, :optional},
      4 => {:retired, :bool},
      5 => {:reference_account, :string, :optional},
      6 => {:attributes, :attributes}
    },
    transaction: %{
      1 => {:uuid, :string},
      2 =>
        {:type,
         {:enum,
          ~w(buy sell inbound_delivery outbound_delivery security_transfer cash_transfer deposit
             removal dividend interest interest_charge tax tax_refund fee fee_refund)a}},
      3 => {:account, :string, :optional},
      4 => {:portfolio, :string, :optional},
      5 => {:other_account, :string, :optional},
      6 => {:other_portfolio, :string, :optional},
      7 => {:other_uuid, :string, :optional},
      9 => {:date_time, :timestamp},
      10 => {:currency, :string},
      11 => {:amount, :int64},
      12 => {:shares, :int64, :optional},
      13 => {:note, :string, :optional},
      14 => {:security, :string, :optional},
      15 => {:units, {:message, :unit}, :repeated},
      17 => {:source, :string, :optional},
      18 => {:ex_date, :local_date_time, :optional}
    },
    unit: %{
      1 => {:type, {:enum, [:gross_value, :tax, :fee]}},
      2 => {:amount, :int64},
      3 => {:currency, :string},
      4 => {:fx_amount, :int64, :optional},
      5 => {:fx_currency, :string, :optional},
      6 => {:fx_rate, :decimal, :optional}
    },
    plan: %{
      1 => {:name, :string},
      2 => {:note, :string, :optional},
      3 => {:security, :string, :optional},
      4 => {:portfolio, :string, :optional},
      5 => {:account, :string, :optional},
      6 => {:attributes, :attributes},
      7 => {:auto_generate, :bool},
      8 => {:start, :epoch_day},
      9 => {:interval, :int32},
      10 => {:amount, :int64},
      11 => {:fees, :int64},
      12 => {:transactions, :string, :repeated},
      13 => {:taxes, :int64},
      14 => {:type, {:enum, [:purchase_or_delivery, :deposit, :removal, :interest]}}
    },
    taxonomy: %{
      1 => {:id, :string},
      2 => {:name, :string},
      3 => {:source, :string, :optional},
      4 => {:dimensions, :string, :repeated},
      5 => {:classifications, {:message, :classification}, :repeated}
    },
    classification: %{
      1 => {:id, :string},
      2 => {:parent_id, :string, :optional},
      3 => {:name, :string},
      4 => {:note, :string, :optional},
      5 => {:color, :string, :optional},
      6 => {:weight, :int32},
      7 => {:rank, :int32},
      9 => {:assignments, {:message, :assignment}, :repeated}
    },
    assignment: %{
      1 => {:vehicle, :string},
      2 => {:weight, :int32},
      3 => {:rank, :int32}
    },
    settings: %{2 => {:attribute_types, {:message, :attribute_type}, :repeated}},
    attribute_type: %{
      1 => {:id, :string},
      2 => {:name, :string},
      3 => {:column_label, :string, :optional},
      5 => {:target, :string, :optional},
      6 => {:value_type, :string, :optional},
      7 => {:converter, :string, :optional}
    },
    key_value: %{1 => {:key, :string}, 2 => {:value, :any, :optional}},
    any: %{
      2 => {:string, :string, :optional},
      3 => {:int32, :int32, :optional},
      4 => {:int64, :int64, :optional},
      5 => {:double, :double, :optional},
      6 => {:bool, :bool, :optional},
      7 => {:map, {:message, :map}, :optional}
    },
    map: %{1 => {:entries, :attributes}},
    timestamp: %{1 => {:seconds, :int64}, 2 => {:nanos, :int32}},
    local_date_time: %{1 => {:epoch_day, :int64}, 2 => {:second_of_day, :int32}},
    decimal: %{1 => {:scale, :uint32}, 3 => {:value, :bytes}}
  }

  @epoch ~D[1970-01-01]

  @doc "Reads a PP file from disk."
  def read(path) do
    case File.read(path) do
      {:ok, bin} -> parse(bin)
      {:error, _} -> {:error, :not_a_pp_file}
    end
  end

  @doc "Parses the contents of a PP file."
  def parse(bin) do
    with {:ok, files} <- unzip(bin) do
      case {List.keyfind(files, ~c"data.portfolio", 0), List.keymember?(files, ~c"data.xml", 0)} do
        {{_, <<"PPPBV1", data::binary>>}, _} -> message(data, :client)
        {nil, true} -> {:error, :xml_format}
        _ -> {:error, :not_a_pp_file}
      end
    end
  end

  defp unzip(bin) do
    case :zip.unzip(bin, [:memory]) do
      {:ok, files} -> {:ok, files}
      {:error, _} -> {:error, :not_a_pp_file}
    end
  end

  defp message(bin, name) do
    spec = Map.fetch!(@messages, name)

    with {:ok, fields} <- Wire.decode(bin),
         {:ok, map} <- collect(fields, spec, defaults(spec)) do
      {:ok, finish(map, spec)}
    end
  end

  defp collect([], _spec, acc), do: {:ok, acc}

  defp collect([{number, raw} | rest], spec, acc) do
    case Map.get(spec, number) do
      nil ->
        collect(rest, spec, acc)

      field ->
        with {:ok, acc} <- put(field, raw, acc), do: collect(rest, spec, acc)
    end
  end

  defp put({name, :attributes}, raw, acc) do
    with {:ok, %{key: key, value: value}} <- message(raw, :key_value) do
      {:ok, Map.update!(acc, name, &Map.put(&1, key, value))}
    end
  end

  defp put({name, type, :repeated}, raw, acc) do
    with {:ok, value} <- convert(type, raw), do: {:ok, Map.update!(acc, name, &[value | &1])}
  end

  defp put({name, type, :optional}, raw, acc), do: put({name, type}, raw, acc)

  defp put({name, type}, raw, acc) do
    with {:ok, value} <- convert(type, raw), do: {:ok, Map.put(acc, name, value)}
  end

  defp defaults(spec) do
    Map.new(spec, fn {_number, field} -> {elem(field, 0), default(field)} end)
  end

  defp default({_, _, :repeated}), do: []
  defp default({_, _, :optional}), do: nil
  defp default({_, :attributes}), do: %{}
  defp default({_, :bool}), do: false
  defp default({_, {:enum, [first | _]}}), do: first
  defp default({_, type}) when type in [:int32, :int64, :uint32], do: 0
  defp default({_, :epoch_day}), do: @epoch
  defp default({_, _}), do: nil

  defp finish(map, spec) do
    Enum.reduce(spec, map, fn
      {_, {name, _, :repeated}}, map -> Map.update!(map, name, &Enum.reverse/1)
      _, map -> map
    end)
  end

  defp convert(:string, raw) when is_binary(raw), do: {:ok, raw}
  defp convert(:bytes, raw) when is_binary(raw), do: {:ok, raw}
  defp convert(:bool, raw) when is_integer(raw), do: {:ok, raw != 0}
  defp convert(:uint32, raw) when is_integer(raw), do: {:ok, raw}

  defp convert(type, raw) when type in [:int32, :int64] and is_integer(raw),
    do: {:ok, Wire.signed(raw)}

  defp convert(:epoch_day, raw) when is_integer(raw),
    do: {:ok, Date.add(@epoch, Wire.signed(raw))}

  defp convert(:double, <<v::float-little-64>>), do: {:ok, v}

  defp convert({:enum, values}, raw) when is_integer(raw) do
    case Enum.at(values, raw) do
      nil -> {:error, :malformed}
      value -> {:ok, value}
    end
  end

  defp convert({:message, name}, raw) when is_binary(raw), do: message(raw, name)

  defp convert(:timestamp, raw) when is_binary(raw) do
    # PP writes local date-times as if they were UTC.
    with {:ok, %{seconds: seconds}} <- message(raw, :timestamp) do
      {:ok, NaiveDateTime.add(~N[1970-01-01 00:00:00], seconds)}
    end
  end

  defp convert(:local_date_time, raw) when is_binary(raw) do
    with {:ok, %{epoch_day: day, second_of_day: second}} <- message(raw, :local_date_time) do
      {:ok, NaiveDateTime.add(~N[1970-01-01 00:00:00], day * 86_400 + second)}
    end
  end

  defp convert(:decimal, raw) when is_binary(raw) do
    # An unscaled two's complement big-endian integer, as Java's BigInteger.toByteArray/0.
    with {:ok, %{scale: scale, value: bytes}} <- message(raw, :decimal) do
      size = bit_size(bytes || <<>>)
      <<unscaled::signed-big-size(^size)>> = bytes || <<>>
      {:ok, Decimal.new(if(unscaled < 0, do: -1, else: 1), abs(unscaled), -scale)}
    end
  end

  defp convert(:any, raw) when is_binary(raw) do
    with {:ok, any} <- message(raw, :any) do
      case any do
        %{map: %{entries: entries}} -> {:ok, entries}
        _ -> {:ok, Enum.find(Map.values(any), &(not is_nil(&1)))}
      end
    end
  end

  defp convert(_type, _raw), do: {:error, :malformed}
end
