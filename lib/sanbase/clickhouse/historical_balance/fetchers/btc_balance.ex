defmodule Sanbase.Clickhouse.HistoricalBalance.BtcBalance do
  @doc ~s"""
  Module for working with historical ethereum balances.

  Includes functions for calculating:
  - Historical balances for an address or a list of addresses. For a list of addresses
  the combined balance is returned
  - Balance changes for an address or a list of addresses. This is used to calculate
  ethereum spent over time. Summing the balance changes of all wallets of a project
  allows to easily handle transactions between project wallets and not count them
  as spent.
  """

  @behaviour Sanbase.Clickhouse.HistoricalBalance.Behaviour
  use Ecto.Schema

  import Sanbase.Clickhouse.HistoricalBalance.Utils

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @btc_decimals 100_000_000

  @table "btc_balances"
  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:balance, :float)
    field(:old_balance, :float, source: :oldBalance)
    field(:address, :string)
  end

  @doc false
  @spec changeset(any(), any()) :: no_return()
  def changeset(_, _),
    do: raise("Should not try to change btc balances")

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def assets_held_by_address(address) do
    {query, args} = current_balance_query(address)

    ClickhouseRepo.query_transform(query, args, fn [value] ->
      %{
        slug: "bitcoin",
        balance: value
      }
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance(address, currency, decimals, from, to, interval)
      when is_binary(address) do
    {query, args} = historical_balance_query(address, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, balance, has_changed] ->
      %{
        datetime: DateTime.from_unix!(dt),
        balance: balance / @btc_decimals,
        has_changed: has_changed
      }
    end)
    |> maybe_update_first_balance(fn -> last_balance_before(address, currency, decimals, from) end)
    |> maybe_fill_gaps_last_seen_balance()
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance(addresses, currency, decimals, from, to, interval)
      when is_list(addresses) do
    result =
      addresses
      |> Sanbase.Parallel.map(fn address ->
        {:ok, balances} = historical_balance(address, currency, decimals, from, to, interval)
        balances
      end)
      |> Enum.zip()
      |> Enum.map(&Tuple.to_list/1)
      |> Enum.map(fn
        [] ->
          []

        [%{datetime: datetime} | _] = list ->
          balance = list |> Enum.map(& &1.balance) |> Enum.sum()
          %{datetime: datetime, balance: balance}
      end)

    {:ok, result}
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def balance_change([], _, _, _, _), do: {:ok, []}

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def balance_change(address_or_addresses, _currency, _decimals, from, to)
      when is_binary(address_or_addresses) or is_list(address_or_addresses) do
    {query, args} = balance_change_query(address_or_addresses, from, to)

    ClickhouseRepo.query_transform(query, args, fn [address, start_balance, end_balance, change] ->
      {address, {start_balance, end_balance, change}}
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance_change([], _, _, _, _, _), do: {:ok, []}

  def historical_balance_change(address_or_addresses, _currency, _decimals, from, to, interval)
      when is_binary(address_or_addresses) or is_list(address_or_addresses) do
    {query, args} = historical_balance_change_query(address_or_addresses, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, change] ->
      %{
        datetime: DateTime.from_unix!(dt),
        balance_change: change
      }
    end)
    |> maybe_drop_not_needed(from)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def last_balance_before(address, _currency, _decimals, datetime) do
    query = """
    SELECT balance
    FROM #{@table}
    PREWHERE
      address = ?1 AND
      dt <=toDateTime(?2)
    ORDER BY dt DESC
    LIMIT 1
    """

    args = [address, DateTime.to_unix(datetime)]

    case ClickhouseRepo.query_transform(query, args, & &1) do
      {:ok, [[balance]]} -> {:ok, balance}
      {:ok, []} -> {:ok, 0}
      {:error, error} -> {:error, error}
    end
  end

  # Private functions

  defp current_balance_query(address) do
    query = """
    SELECT balance
    FROM #{@table}
    PREWHERE
      address = ?1 AND
    ORDER BY dt DESC
    LIMIT 1
    """

    args = [address]
    {query, args}
  end

  defp historical_balance_query(address, from, to, interval) when is_binary(address) do
    interval = Sanbase.DateTimeUtils.str_to_sec(interval)
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    span = div(to_unix - from_unix, interval) |> max(1)

    query = """
    SELECT time, SUM(balance), toUInt8(SUM(has_changed))
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) AS time,
          toFloat64(0) AS balance,
          toInt8(0) AS has_changed
        FROM numbers(?2)

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
        argMax(balance, dt) AS balance,
        toUInt8(1) AS has_changed
      FROM #{@table}
      PREWHERE
        address = ?3 AND
        dt >= toDateTime(?4) AND
        dt <= toDateTime(?5)
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [interval, span, address, from_unix, to_unix]
    {query, args}
  end

  defp balance_change_query(address_or_addresses, from, to) do
    addresses = address_or_addresses |> List.wrap() |> List.flatten()

    query = """
    SELECT
      address,
      argMaxIf(balance, dt, dt <= ?3) AS start_balance,
      argMaxIf(balance, dt, dt <= ?4) AS end_balance,
      end_balance - start_balance AS diff
    FROM #{@table} FINAL
    PREWHERE
      address IN (?1)
    GROUP BY address
    """

    args = [addresses, from, to]

    {query, args}
  end

  defp historical_balance_change_query(address_or_addresses, from, to, interval) do
    addresses = address_or_addresses |> List.wrap() |> List.flatten()

    interval = Sanbase.DateTimeUtils.str_to_sec(interval)
    to_unix = DateTime.to_unix(to)
    from_unix = DateTime.to_unix(from)
    span = div(to_unix - from_unix, interval) |> max(1)

    # The balances table is like a stack. For each balance change there is a record
    # with sign = -1 that is the old balance and with sign = 1 which is the new balance
    query = """
    SELECT time, SUM(change)
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) AS time,
          toFloat64(0) AS change
        FROM numbers(?2)

      UNION ALL

      SELECT
        toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
        balance - oldBalance AS change
      FROM #{@table} FINAL
      PREWHERE
        address in (?3) AND
        dt >= toDateTime(?4) AND
        dt <= toDateTime(?5)
      GROUP BY address
    )
    GROUP BY time
    ORDER BY time
    """

    args = [interval, span, addresses, from_unix, to_unix]
    {query, args}
  end
end
