defmodule Sanbase.Clickhouse.Exchanges.Trades do
  use Ecto.Schema

  @exchanges ["Binance", "Bitfinex", "Kraken", "Poloniex", "Bitrex"]

  alias Sanbase.ClickhouseRepo

  @table "exchange_trades"
  schema @table do
    field(:timestamp, :utc_datetime)
    field(:source, :string)
    field(:symbol, :string)
    field(:side, :string)
    field(:amount, :float)
    field(:price, :float)
    field(:cost, :float)
  end

  @doc false
  @spec changeset(any(), any()) :: no_return()
  def changeset(_, _),
    do: raise("Should not try to change exchange trades")

  def last_exchange_trades(exchange, ticker_pair, limit) when exchange in @exchanges do
    {query, args} = last_exchange_trades_query(exchange, ticker_pair, limit)

    ClickhouseRepo.query_transform(query, args, fn
      [timestamp, source, symbol, side, amount, price, cost] ->
        %{
          exchange: source,
          ticker_pair: symbol,
          datetime: timestamp |> DateTime.from_unix!(),
          side: String.to_existing_atom(side),
          amount: amount,
          cost: cost,
          price: price
        }
    end)
  end

  def exchange_trades(exchange, ticker_pair, from, to) when exchange in @exchanges do
    {query, args} = exchange_trades_query(exchange, ticker_pair, from, to)

    ClickhouseRepo.query_transform(query, args, fn
      [timestamp, source, symbol, side, amount, price, cost] ->
        %{
          exchange: source,
          ticker_pair: symbol,
          datetime: timestamp |> DateTime.from_unix!(),
          side: String.to_existing_atom(side),
          amount: amount,
          cost: cost,
          price: price
        }
    end)
  end

  def exchange_trades(exchange, ticker_pair, from, to, interval) when exchange in @exchanges do
    {query, args} = exchange_trades_aggregated_query(exchange, ticker_pair, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn
      [timestamp, total_amount, avg_price, total_cost, side] ->
        %{
          exchange: exchange,
          ticker_pair: ticker_pair,
          datetime: timestamp |> DateTime.from_unix!(),
          side: String.to_existing_atom(side),
          amount: total_amount,
          cost: total_cost,
          price: avg_price
        }
    end)
  end

  defp last_exchange_trades_query(exchange, ticker_pair, limit) do
    query = """
    SELECT
      toUnixTimestamp(dt), source, symbol, side, amount, price, cost
    FROM #{@table}
    PREWHERE
      source = ?1 AND symbol = ?2
    ORDER BY dt DESC
    LIMIT ?3
    """

    args = [
      exchange,
      ticker_pair,
      limit
    ]

    {query, args}
  end

  defp exchange_trades_query(exchange, ticker_pair, from, to) do
    query = """
    SELECT
      toUnixTimestamp(dt), source, symbol, side, amount, price, cost
    FROM #{@table}
    PREWHERE
      source = ?1 AND symbol = ?2 AND
      dt >= toDateTime(?3) AND
      dt <= toDateTime(?4)
    ORDER BY dt
    """

    args = [
      exchange,
      ticker_pair,
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix()
    ]

    {query, args}
  end

  defp exchange_trades_aggregated_query(exchange, ticker_pair, from, to, interval) do
    interval = Sanbase.DateTimeUtils.str_to_sec(interval)
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    span = div(to_datetime_unix - from_datetime_unix, interval) |> max(1)

    query = """
    SELECT time, side2, sum(total_amount), sum(avg_price), sum(total_cost)
    FROM (
      SELECT
        toUnixTimestamp(intDiv(toUInt32(?5 + number * ?1), ?1) * ?1) as time,
        toFloat64(0) AS total_amount,
        toFloat64(0) AS total_cost,
        toFloat64(0) AS avg_price,
        toLowCardinality('sell') as side2
      FROM numbers(?2)

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(?5 + number * ?1), ?1) * ?1) as time,
        toFloat64(0) AS total_amount,
        toFloat64(0) AS total_cost,
        toFloat64(0) AS avg_price,
        toLowCardinality('buy') as side2
      FROM numbers(?2)

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) as time,
        sum(total_amount) AS total_amount,
        sum(total_cost) AS total_cost,
        avg(avg_price) as avg_price,
        side as side2
      FROM (
        SELECT
          any(source), any(symbol), dt,
          sum(amount) as total_amount,
          sum(cost) as total_cost,
          avg(price) as avg_price,
          side
        FROM #{@table}
        PREWHERE
          source = ?3 AND symbol = ?4 AND
          dt >= toDateTime(?5) AND
          dt < toDateTime(?6)
      GROUP BY dt, side
      )
      GROUP BY time, side
      ORDER BY time, side
    )
    GROUP BY time, side2
    ORDER BY time, side2
    """

    args = [
      interval,
      span + 1,
      exchange,
      ticker_pair,
      from_datetime_unix,
      to_datetime_unix
    ]

    {query, args}
  end
end
