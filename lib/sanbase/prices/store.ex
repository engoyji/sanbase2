defmodule Sanbase.Prices.Store do
  @moduledoc ~s"""
    A module for storing and fetching pricing data from a time series data store
    Currently using InfluxDB for the time series data.

    There is a single database at the moment, which contains simple average
    price data for a given currency pair within a given interval. The current
    interval is about 5 mins (+/- 3 seconds). The timestamps are stored as
    nanoseconds
  """
  use Sanbase.Influxdb.Store

  require Logger

  alias __MODULE__
  alias Sanbase.Influxdb.Measurement

  @last_history_price_cmc_measurement "sanbase-internal-last-history-price-cmc"
  def last_history_price_cmc_measurement() do
    @last_history_price_cmc_measurement
  end

  @doc ~s"""
    Fetch all price points in the given `from-to` time interval from `measurement`.
  """
  def fetch_price_points(measurement, from, to) do
    fetch_query(measurement, from, to)
    |> Store.query()
    |> parse_time_series()
  end

  @doc ~s"""
    Fetch open, close, high, low price values for every interval between from-to
  """
  def fetch_ohlc(measurement, from, to, interval) do
    fetch_ohlc_query(measurement, from, to, interval)
    |> Store.query()
    |> parse_time_series()
  end

  @doc ~s"""
    Fetch all price points in the given `from-to` time interval from `measurement`.
  """
  def fetch_price_points!(measurement, from, to) do
    case fetch_price_points(measurement, from, to) do
      {:ok, result} ->
        result

      {:error, error} ->
        raise(error)
    end
  end

  def fetch_prices_with_resolution(measurement, from, to, resolution) do
    fetch_prices_with_resolution_query(measurement, from, to, resolution)
    |> Store.query()
    |> parse_time_series()
  end

  def fetch_prices_with_resolution!(pair, from, to, resolution) do
    case fetch_prices_with_resolution(pair, from, to, resolution) do
      {:ok, result} ->
        result

      {:error, error} ->
        raise(error)
    end
  end

  def fetch_mean_volume(measurement, from, to) do
    fetch_mean_volume_query(measurement, from, to)
    |> Store.query()
    |> parse_time_series()
  end

  def update_last_history_datetime_cmc(ticker_cmc_id, last_updated_datetime) do
    %Measurement{
      timestamp: 0,
      fields: %{last_updated: last_updated_datetime |> DateTime.to_unix(:nanoseconds)},
      tags: [ticker_cmc_id: ticker_cmc_id],
      name: @last_history_price_cmc_measurement
    }
    |> Store.import()
  end

  def last_history_datetime_cmc(ticker_cmc_id) do
    last_history_datetime_cmc_query(ticker_cmc_id)
    |> Store.query()
    |> parse_time_series()
    |> case do
      {:ok, [[_, iso8601_datetime | _rest]]} ->
        {:ok, datetime} = DateTime.from_unix(iso8601_datetime, :nanoseconds)
        {:ok, datetime}

      {:ok, nil} ->
        {:ok, nil}

      {:ok, []} ->
        {:ok, nil}

      {:error, error} ->
        {:error, error}
    end
  end

  def last_history_datetime_cmc!(ticker) do
    case last_history_datetime_cmc(ticker) do
      {:ok, datetime} -> datetime
      {:error, error} -> raise(error)
    end
  end

  def fetch_last_price_point_before(measurement, timestamp) do
    fetch_last_price_point_before_query(measurement, timestamp)
    |> Store.query()
    |> parse_time_series()
  end

  def fetch_combined_vol_mcap(measurements_str, from, to) do
    fetch_combined_vol_mcap_query(measurements_str, from, to)
    |> Store.query()
    |> combine_results_multiple_measurements()
  end

  def all_with_data_after_datetime(datetime) do
    datetime_unix_ns = DateTime.to_unix(datetime, :nanoseconds)

    ~s/SELECT last_updated, ticker_cmc_id FROM "#{@last_history_price_cmc_measurement}"
    WHERE ticker_cmc_id != "" AND last_updated >= #{datetime_unix_ns}/
    |> Store.query()
    |> parse_time_series()
  end

  # Helper functions

  defp fetch_query(measurement, from, to) do
    ~s/SELECT time, price_usd, price_btc, marketcap_usd, volume_usd
    FROM "#{measurement}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp fetch_ohlc_query(measurement, from, to, interval) do
    ~s/SELECT 
     time,
     first(price_usd) as open,
     max(price_usd) as high,
     min(price_usd) as low,
     last(price_usd) as close
     FROM "#{measurement}"
     WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
     AND time <= #{DateTime.to_unix(to, :nanoseconds)}
     GROUP BY time(#{interval})
     FILL(0)/
  end

  defp fetch_prices_with_resolution_query(measurement, from, to, resolution) do
    ~s/SELECT MEAN(price_usd), MEAN(price_btc), MEAN(marketcap_usd), LAST(volume_usd)
    FROM "#{measurement}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}
    GROUP BY time(#{resolution}) fill(none)/
  end

  defp fetch_last_price_point_before_query(measurement, timestamp) do
    ~s/SELECT LAST(price_usd), price_btc, marketcap_usd, volume_usd
    FROM "#{measurement}"
    WHERE time <= #{DateTime.to_unix(timestamp, :nanoseconds)}/
  end

  defp fetch_mean_volume_query(measurement, from, to) do
    ~s/SELECT MEAN(volume_usd)
    FROM "#{measurement}"
    WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
    AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp last_history_datetime_cmc_query(ticker_cmc_id) do
    ~s/SELECT * FROM "#{@last_history_price_cmc_measurement}"
    WHERE ticker_cmc_id = '#{ticker_cmc_id}'/
  end

  defp fetch_combined_vol_mcap_query(measurements_str, from, to) do
    ~s/
      SELECT SUM(volume_usd) as volume_sum, SUM(marketcap_usd) as marketcap_sum
      FROM #{measurements_str}
      WHERE time >= #{DateTime.to_unix(from, :nanoseconds)}
      AND time <= #{DateTime.to_unix(to, :nanoseconds)}/
  end

  defp combine_results_multiple_measurements(%{results: [%{series: series}]}) do
    values = series |> Enum.map(& &1.values)
    combined_volume = values |> Enum.reduce(0, fn [[_, vol, _]], acc -> acc + vol end)
    combined_mcap = values |> Enum.reduce(0, fn [[_, _, mcap]], acc -> acc + mcap end)
    {:ok, combined_volume, combined_mcap}
  end
end
