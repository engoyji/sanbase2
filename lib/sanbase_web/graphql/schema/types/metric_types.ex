defmodule SanbaseWeb.Graphql.MetricTypes do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias Sanbase.Metric

  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.AccessControl
  alias SanbaseWeb.Graphql.Resolvers.MetricResolver

  enum :products_enum do
    value(:sanapi)
    value(:sanbase)
  end

  enum :plans_enum do
    value(:free)
    value(:basic)
    value(:pro)
    value(:custom)
  end

  enum :selector_name do
    value(:slug)
    value(:text)
    value(:owner)
    value(:label)
    value(:holders_count)
    value(:market_segments)
    value(:ignored_slugs)
  end

  input_object :metric_target_selector_input_object do
    field(:slug, :string)
    field(:text, :string)
    field(:owner, :string)
    field(:label, :string)
    field(:holders_count, :integer)
    field(:market_segments, list_of(:string))
    field(:ignored_slugs, list_of(:string))
  end

  input_object :timeseries_metric_transform_input_object do
    field(:type, non_null(:string))
    field(:moving_average_base, :integer)
  end

  enum :metric_data_type do
    value(:timeseries)
    value(:histogram)
  end

  object :metric_data do
    field(:datetime, non_null(:datetime))
    field(:value, :float)
  end

  object :string_list do
    field(:data, list_of(:string))
  end

  object :float_list do
    field(:data, list_of(:float))
  end

  object :float_range_float_value_list do
    field(:data, list_of(:float_range_float_value))
  end

  object :float_range_float_value do
    field(:range, list_of(:float))
    field(:value, :float)
  end

  object :datetime_range_float_value_list do
    field(:data, list_of(:datetime_range_float_value))
  end

  object :datetime_range_float_value do
    field(:range, list_of(:datetime))
    field(:value, :float)
  end

  union :value_list do
    description("Type Parameterized Array")

    types([
      :string_list,
      :float_list,
      :float_range_float_value_list,
      :datetime_range_float_value_list
    ])

    resolve_type(fn
      %{data: [value | _]}, _ when is_number(value) ->
        :float_list

      %{data: [value | _]}, _ when is_binary(value) ->
        :string_list

      %{data: [%{range: [r | _], value: value} | _]}, _ when is_number(r) and is_number(value) ->
        :float_range_float_value_list

      %{data: [%{range: [%DateTime{} | _], value: value} | _]}, _ when is_number(value) ->
        :datetime_range_float_value_list

      %{data: []}, _ ->
        :float_list
    end)
  end

  object :histogram_data do
    field(:labels, list_of(:string))
    field(:values, :value_list)
  end

  object :metric_metadata do
    @desc ~s"""
    The name of the metric the metadata is about
    """
    field(:metric, non_null(:string))

    @desc ~s"""
    A human readable name of the metric.
    For example the human readable name of `mvrv_usd_5y` is `MVRV for coins that moved in the past 5 years`
    """
    field :human_readable_name, non_null(:string) do
      cache_resolve(&MetricResolver.get_human_readable_name/3, ttl: 3600)
    end

    @desc ~s"""
    List of slugs which can be provided to the `timeseriesData` field to fetch
    the metric.
    """
    field :available_slugs, list_of(:string) do
      cache_resolve(&MetricResolver.get_available_slugs/3, ttl: 600)
    end

    @desc ~s"""
    The minimal granularity for which the data is available.
    """
    field(:min_interval, :string)

    @desc ~s"""
    When the interval provided in the query is bigger than `min_interval` and
    contains two or more data points, the data must be aggregated into a single
    data point. The default aggregation that is applied is this `default_aggregation`.
    The default aggregation can be changed by the `aggregation` parameter of
    the `timeseriesData` field. Available aggregations are:
    [
    #{
      (Metric.available_aggregations() -- [nil])
      |> Enum.map(&Atom.to_string/1)
      |> Enum.map(&String.upcase/1)
      |> Enum.join(",")
    }
    ]
    """
    field(:default_aggregation, :aggregation)

    @desc ~s"""
    The supported aggregations for this metric. For more information about
    aggregations see the documentation for `defaultAggregation`
    """
    field(:available_aggregations, list_of(:aggregation))

    @desc ~s"""
    The supported selector types for the metric. It is used to choose the
    target for which the metric is computed. Available selectors are:
      - slug - Identifies an asset/project
      - text - Provides random text/search term for the social metrics
      - holders_count - Provides the number of holders used in holders metrics

    Every metric has `availableSelectors` in its metadata, showing exactly
    which of the selectors can be used.
    """
    field(:available_selectors, list_of(:selector_name))

    @desc ~s"""
    The data type of the metric can be either timeseries or histogram.
      - Timeseries data is a sequence taken at successive equally spaced points
        in time (every 5 minutes, every day, every year, etc.).
      - Histogram data is an approximate representation of the distribution of
        numerical or categorical data. The metric is represented as a list of data
        points, where every point is represented represented by a tuple containing
        a range an a value.
    """
    field(:data_type, :metric_data_type)

    field(:is_accessible, :boolean)

    field(:is_restricted, :boolean)

    field(:restricted_from, :datetime)

    field(:restricted_to, :datetime)
  end

  object :metric do
    @desc ~s"""
    Return a list of 'datetime' and 'value' for a given metric, slug
    and time period.

    The 'includeIncompleteData' flag has a default value 'false'.

    Some metrics may have incomplete data for the last data point (usually today)
    as they are computed since the beginning of the day. An example is daily
    active addresses for today - at 12:00pm it will contain the data only
    for the last 12 hours, not for a whole day. This incomplete data can be
    confusing so it is excluded by default. If this incomplete data is needed,
    the flag includeIncompleteData should be set to 'true'.

    Incomplete data can still be useful. Here are two examples:
    Daily Active Addresses: The number is only going to increase during the day,
    so if the intention is to see when they reach over a threhsold the incomplete
    data gives more timely signal.

    NVT: Due to the way it is computed, the value is only going to decrease
    during the day, so if the intention is to see when it falls below a threhsold,
    the incomplete gives more timely signal.
    """
    field :timeseries_data, list_of(:metric_data) do
      arg(:slug, :string)
      arg(:selector, :metric_target_selector_input_object)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")
      arg(:aggregation, :aggregation, default_value: nil)
      arg(:transform, :timeseries_metric_transform_input_object)
      arg(:include_incomplete_data, :boolean, default_value: false)

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)

      cache_resolve(&MetricResolver.timeseries_data/3)
    end

    @desc ~s"""
    A derivative of the `timeseriesData` - read its full descriptio if not
    familiar with it.

    `aggregatedTimeseriesData` returns a single float value instead of list
    of datetimes and values. The single values is computed by aggregating all
    of the values in the specified from-to range with the `aggregation` aggregation.
    """
    field :aggregated_timeseries_data, :float do
      arg(:slug, :string)
      arg(:selector, :metric_target_selector_input_object)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:aggregation, :aggregation, default_value: nil)

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)

      cache_resolve(&MetricResolver.aggregated_timeseries_data/3)
    end

    @desc ~s"""
    Returns the complexity that the metric would have given the timerange
    arguments. The complexity is computed as if both `value` and `datetime` fields
    are queried.
    """
    field :timeseries_data_complexity, :integer do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      resolve(&MetricResolver.timeseries_data_complexity/3)
    end

    @desc ~s"""
    A histogram is an approximate representation of the distribution of numerical or
    categorical data.

    The metric is represented as a list of data points, where every point is
    represented represented by a tuple containing a range an a value.

    Example (histogram data) The price_histogram (or spent_coins_cost) shows at what
    price were acquired the coins/tokens transacted on a given day D. The metric is
    represented as a list of price ranges and values with the following meaning: Out
    of all coins/tokens transacted on day D, value amount of them were acquired when
    the price was in the range range.

    On April 07, the bitcoins that circulated during that day were 124k and the
    average price for the day was $7307. Out of all of the 124k bitcoins, 13.8k of
    them were acquired when the price was in the range $8692.08 - $10845.62, so
    they were last moved when the price was higher. The same logic applies for all
    of the ranges.

    [
      ...
      {
        "range": [7307.7, 8692.08],
        "value": 2582.64
      },
      {
        "range": [8692.08, 10845.62],
        "value": 13804.97
      },
      {
        "range": [10845.62, 12999.16],
        "value": 130.33
      },
      ...
    ]
    """
    field :histogram_data, :histogram_data do
      arg(:slug, :string)
      arg(:selector, :metric_target_selector_input_object)
      # from datetime arg is not required for `all_spent_coins_cost` metric which calculates
      # the histogram for all time.
      arg(:from, :datetime)
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")
      arg(:limit, :integer, default_value: 20)

      # Complexity disabled due to not required `from` param. If at some point
      # the complexity is re-enabled, the document provider need to be updated
      # so `histogram_data` is inlcuded in the list of selections for which
      # the metric name is stored in process dictionary for complexity computation
      # complexity(&Complexity.from_to_interval/3)

      middleware(AccessControl)

      cache_resolve(&MetricResolver.histogram_data/3)
    end

    field :available_since, :datetime do
      arg(:slug, :string)
      arg(:selector, :metric_target_selector_input_object)
      cache_resolve(&MetricResolver.available_since/3)
    end

    field :last_datetime_computed_at, :datetime do
      arg(:slug, :string)
      arg(:selector, :metric_target_selector_input_object)
      cache_resolve(&MetricResolver.last_datetime_computed_at/3)
    end

    field :metadata, :metric_metadata do
      cache_resolve(&MetricResolver.get_metadata/3)
    end
  end
end
