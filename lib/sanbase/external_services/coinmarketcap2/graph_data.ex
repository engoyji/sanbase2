defmodule Sanbase.ExternalServices.Coinmarketcap.GraphData2 do
  defstruct [:market_cap_by_available_supply, :price_usd, :volume_usd, :price_btc]

  require Logger

  use Tesla

  # TODO: Change after switching over to only this cmc
  alias __MODULE__, as: GraphData
  alias Sanbase.ExternalServices.Coinmarketcap.PricePoint2, as: PricePoint
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Model.Project
  alias Sanbase.Prices.Store

  plug(Sanbase.ExternalServices.RateLimiting.Middleware, name: :graph_coinmarketcap_rate_limiter)
  plug(Sanbase.ExternalServices.ErrorCatcher.Middleware)
  plug(Tesla.Middleware.BaseUrl, "https://graphs2.coinmarketcap.com")
  plug(Tesla.Middleware.Compression)
  plug(Tesla.Middleware.Logger)

  # Number of seconds in a day
  @seconds_in_day 24 * 60 * 60

  def fetch_first_datetime("TOTAL_MARKET") do
    all_time_total_market_price_points()
    |> List.first()
    |> case do
      nil -> nil
      %PricePoint{datetime: datetime} -> datetime
    end
  end

  def fetch_first_datetime(coinmarketcap_id) do
    all_time_project_price_points(coinmarketcap_id)
    |> List.first()
    |> case do
      nil -> nil
      %PricePoint{datetime: datetime} -> datetime
    end
  end

  def fetch_and_store_prices(_project, nil), do: :ok

  def fetch_and_store_prices(
        %Project{coinmarketcap_id: coinmarketcap_id} = project,
        last_fetched_datetime
      ) do
    fetch_price_stream(coinmarketcap_id, last_fetched_datetime, DateTime.utc_now())
    |> process_price_stream(project)
  end

  def fetch_price_stream(coinmarketcap_id, from_datetime, to_datetime) do
    day_ranges(from_datetime, to_datetime)
    |> Stream.map(&extract_price_points_for_interval(coinmarketcap_id, &1))
  end

  def fetch_and_store_marketcap_total(nil), do: :ok

  def fetch_and_store_marketcap_total(last_fetched_datetime) do
    fetch_marketcap_total_stream(last_fetched_datetime, DateTime.utc_now())
    |> process_marketcap_total_stream()
  end

  def fetch_marketcap_total_stream(from_datetime, to_datetime) do
    day_ranges(from_datetime, to_datetime)
    |> Stream.map(&extract_price_points_for_interval("TOTAL_MARKET", &1))
  end

  # Helper functions

  defp process_marketcap_total_stream(marketcap_total_stream) do
    measurement_name = "TOTAL_MARKET_total-market"

    marketcap_total_stream
    # Store each data point and the information when it was last updated
    |> Stream.each(fn total_marketcap_info ->
      measurement_points =
        total_marketcap_info
        |> Enum.flat_map(&PricePoint.price_points_to_measurements(&1, measurement_name))

      measurement_points |> Store.import()

      update_last_cmc_history_datetime(measurement_name, measurement_points)
    end)
    |> Stream.run()
  end

  defp process_price_stream(price_stream, %Project{} = project) do
    price_stream
    # Store each data point and the information when it was last updated
    |> Stream.each(fn prices ->
      measurement_points =
        prices
        |> Enum.flat_map(&PricePoint.price_points_to_measurements(&1, project))

      measurement_points |> Store.import()

      update_last_cmc_history_datetime(project, measurement_points)
    end)
    |> Stream.run()
  end

  def update_last_cmc_history_datetime(_project, []), do: :ok

  def update_last_cmc_history_datetime(%Project{} = project, points) do
    measurement_name = Measurement.name_from(project)

    last_price_datetime_updated =
      points
      |> Enum.max_by(&Measurement.get_timestamp/1)
      |> Measurement.get_datetime()

    Store.update_last_history_datetime_cmc(measurement_name, last_price_datetime_updated)
  end

  defp json_to_price_points(json) do
    json
    |> Poison.decode!(as: %GraphData{})
    |> convert_to_price_points()
  end

  defp all_time_project_price_points(coinmarketcap_id) do
    all_time_project_url(coinmarketcap_id)
    |> get()
    |> case do
      %{status: 200, body: body} ->
        body |> json_to_price_points()
    end
  end

  defp all_time_total_market_price_points() do
    all_time_total_market_url()
    |> get()
    |> case do
      %{status: 200, body: body} ->
        body |> json_to_price_points()
    end
  end

  defp convert_to_price_points(%GraphData{
         market_cap_by_available_supply: market_cap_by_available_supply,
         price_usd: nil,
         volume_usd: volume_usd,
         price_btc: nil
       }) do
    List.zip([market_cap_by_available_supply, volume_usd])
    |> Enum.map(fn {[dt, marketcap], [dt, volume_usd]} ->
      %PricePoint{
        marketcap_usd: marketcap,
        volume_usd: volume_usd,
        datetime: DateTime.from_unix!(dt, :millisecond)
      }
    end)
  end

  defp convert_to_price_points(%GraphData{
         market_cap_by_available_supply: market_cap_by_available_supply,
         price_usd: price_usd,
         price_btc: price_btc,
         volume_usd: volume_usd
       }) do
    List.zip([market_cap_by_available_supply, price_usd, volume_usd, price_btc])
    |> Enum.map(fn {[dt, marketcap], [dt, price_usd], [dt, volume_usd], [dt, price_btc]} ->
      %PricePoint{
        price_usd: price_usd,
        price_btc: price_btc,
        marketcap_usd: marketcap,
        volume_usd: volume_usd,
        datetime: DateTime.from_unix!(dt, :millisecond)
      }
    end)
  end

  defp extract_price_points_for_interval("TOTAL_MARKET", {start_interval_sec, end_interval_sec}) do
    total_market_interval_url(start_interval_sec * 1000, end_interval_sec * 1000)
    |> get()
    |> case do
      %{status: 200, body: body} ->
        body |> json_to_price_points()

      _ ->
        Logger.error("Failed to fetch graph data for total marketcap for the selected interval")
        []
    end
  end

  defp extract_price_points_for_interval(coinmarketcap_id, {start_interval_sec, end_interval_sec}) do
    project_interval_url(
      coinmarketcap_id,
      start_interval_sec * 1000,
      end_interval_sec * 1000
    )
    |> get()
    |> case do
      %{status: 200, body: body} ->
        body |> json_to_price_points()

      _ ->
        Logger.error(
          "Failed to fetch graph data for #{coinmarketcap_id} for the selected interval"
        )

        []
    end
  end

  defp day_ranges(from_datetime, to_datetime)
       when not is_number(from_datetime) and not is_number(to_datetime) do
    day_ranges(DateTime.to_unix(from_datetime), DateTime.to_unix(to_datetime))
  end

  defp day_ranges(from_datetime, to_datetime) do
    Stream.unfold(from_datetime, fn start_interval ->
      if start_interval <= to_datetime do
        {
          {start_interval, start_interval + @seconds_in_day},
          start_interval + @seconds_in_day
        }
      else
        nil
      end
    end)
  end

  defp all_time_project_url(coinmarketcap_id) do
    "/currencies/#{coinmarketcap_id}/"
  end

  defp project_interval_url(coinmarketcap_id, from_timestamp, to_timestamp) do
    "/currencies/#{coinmarketcap_id}/#{from_timestamp}/#{to_timestamp}/"
  end

  defp all_time_total_market_url() do
    "/global/marketcap-total/"
  end

  defp total_market_interval_url(from_timestamp, to_timestamp) do
    "/global/marketcap-total/#{from_timestamp}/#{to_timestamp}/"
  end
end
