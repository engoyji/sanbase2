defmodule SanbaseWeb.Graphql.MetricAnomalyTest do
  use SanbaseWeb.ConnCase, async: false
  use Mockery

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  setup do
    project = insert(:project, %{name: "Santiment", ticker: "SAN", slug: "santiment"})

    [
      project: project,
      datetime1: DateTime.from_naive!(~N[2017-05-13 21:45:00], "Etc/UTC"),
      datetime2: DateTime.from_naive!(~N[2017-05-13 21:55:00], "Etc/UTC")
    ]
  end

  test "tech_indicators returns correct result", context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body: """
         [
           {"datetime":"2019-02-23T00:00:00+00:00","value":30},
           {"datetime":"2019-02-24T00:00:00+00:00","value":40}
         ]
         """,
         status_code: 200
       }}
    )

    query = anomalies_query(context)

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "metricAnomaly"))
      |> json_response(200)
      |> get_in(["data", "metricAnomaly"])

    assert result == [
             %{"datetime" => "2019-02-23T00:00:00Z", "metricValue" => 30},
             %{"datetime" => "2019-02-24T00:00:00Z", "metricValue" => 40}
           ]
  end

  test "tech_indicators returns empty result", context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body: "[]",
         status_code: 200
       }}
    )

    query = anomalies_query(context)

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "metricAnomaly"))
      |> json_response(200)
      |> get_in(["data", "metricAnomaly"])

    assert result == []
  end

  test "tech_indicators returns error", context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body: "Internal Server Error",
         status_code: 500
       }}
    )

    query = anomalies_query(context)

    assert capture_log(fn ->
             result =
               context.conn
               |> post("/graphql", query_skeleton(query, "metricAnomaly"))
               |> json_response(200)

             assert result["data"] == %{"metricAnomaly" => nil}
             error = result["errors"] |> List.first()
             assert error["message"] =~ "Error executing query. See logs for details"
           end) =~
             "Error status 500 fetching anomalies for project with slug: santiment for metric daily_active_addresses - Internal Server Error"
  end

  # Private functions

  defp anomalies_query(context) do
    """
    {
      metricAnomaly(
        metric: DAILY_ACTIVE_ADDRESSES,
        slug: "#{context.project.slug}"
        from: "#{context.datetime1}"
        to: "#{context.datetime2}"
      ) {
        datetime
        metricValue
      }
    }
    """
  end
end
