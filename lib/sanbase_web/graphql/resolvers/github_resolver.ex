defmodule SanbaseWeb.Graphql.Resolvers.GithubResolver do
  require Logger

  import Sanbase.Utils.ErrorHandling, only: [handle_graphql_error: 3, handle_graphql_error: 4]

  alias SanbaseWeb.Graphql.Helpers.Utils
  alias Sanbase.Model.Project

  def dev_activity(
        _root,
        %{
          slug: slug,
          from: from,
          to: to,
          interval: interval,
          transform: transform,
          moving_average_interval_base: moving_average_interval_base
        },
        _resolution
      ) do
    with {:ok, github_organizations} <- Project.github_organizations(slug),
         {:ok, result} <-
           Sanbase.Clickhouse.Github.dev_activity(
             github_organizations,
             from,
             to,
             interval,
             transform,
             moving_average_interval_base
           ) do
      {:ok, result}
    else
      {:error, error} ->
        {:error, handle_graphql_error("dev_activity", slug, error)}
    end
  end

  def dev_activity(
        _root,
        %{
          selector: %{slug: slug},
          from: from,
          to: to,
          interval: interval,
          transform: transform,
          moving_average_interval_base: moving_average_interval_base
        },
        _resolution
      ) do
    with {:ok, github_organizations} <- Project.github_organizations(slug),
         {:ok, result} <-
           Sanbase.Clickhouse.Github.dev_activity(
             github_organizations,
             from,
             to,
             interval,
             transform,
             moving_average_interval_base
           ) do
      {:ok, result}
    else
      {:error, {:github_link_error, _error}} ->
        {:ok, []}

      error ->
        {:error, handle_graphql_error("dev_activity", slug, error)}
    end
  end

  def dev_activity(
        _root,
        %{
          selector: %{market_segments: market_segments},
          from: from,
          to: to,
          interval: interval,
          transform: transform,
          moving_average_interval_base: moving_average_interval_base
        },
        _resolution
      ) do
    args = %{
      transform: %{type: transform, moving_average_base: moving_average_interval_base},
      from: from,
      to: to,
      interval: interval,
      selector: %{}
    }

    with projects when is_list(projects) <-
           Project.List.by_market_segment_all_of(market_segments),
         slugs <- Enum.map(projects, & &1.slug),
         {:ok, result} <- get_dev_activity_many_slugs(slugs, args) do
      {:ok, result}
    else
      {:error, error} ->
        {:error,
         handle_graphql_error("dev_activity", market_segments, error,
           description: "market segments"
         )}
    end
  end

  def dev_activity(
        _root,
        %{
          selector: %{organizations: organizations},
          from: from,
          to: to,
          interval: interval,
          transform: transform,
          moving_average_interval_base: moving_average_interval_base
        },
        _resolution
      ) do
    case Sanbase.Clickhouse.Github.dev_activity(
           organizations,
           from,
           to,
           interval,
           transform,
           moving_average_interval_base
         ) do
      {:ok, result} ->
        {:ok, result}

      error ->
        {:error,
         handle_graphql_error("dev_activity", organizations, error, description: "organizations")}
    end
  end

  def github_activity(
        _root,
        %{
          slug: slug,
          from: from,
          to: to,
          interval: interval,
          transform: transform,
          moving_average_interval_base: moving_average_interval_base
        },
        _resolution
      ) do
    with {:ok, github_organizations} <- Project.github_organizations(slug),
         {:ok, from, to, interval} <-
           Utils.calibrate_interval(
             Sanbase.Clickhouse.Github,
             github_organizations,
             from,
             to,
             interval,
             24 * 60 * 60
           ),
         {:ok, result} <-
           Sanbase.Clickhouse.Github.github_activity(
             github_organizations,
             from,
             to,
             interval,
             transform,
             moving_average_interval_base
           ) do
      {:ok, result}
    else
      {:error, error} ->
        {:error, handle_graphql_error("github_activity", slug, error)}
    end
  end

  def available_repos(_root, _args, _resolution) do
    {:ok, Project.List.project_slugs_with_organization()}
  end

  # Private functions
  defp get_dev_activity_many_slugs(slugs, args) do
    result =
      slugs
      |> Enum.chunk_every(500)
      |> Enum.map(fn slugs ->
        SanbaseWeb.Graphql.Resolvers.MetricResolver.timeseries_data(
          %{},
          %{args | selector: %{slug: slugs}},
          %{source: %{metric: "dev_activity_1d"}}
        )
      end)

    case Enum.find(result, &match?({:error, _}, &1)) do
      nil ->
        result =
          result
          |> Enum.flat_map(fn {:ok, data} -> data end)
          |> Enum.group_by(fn %{datetime: dt} -> dt end, fn %{value: value} -> value end)
          |> Enum.map(fn {datetime, values} ->
            %{datetime: datetime, activity: Enum.sum(values)}
          end)
          |> Enum.sort_by(& &1.datetime, {:asc, DateTime})

        {:ok, result}

      error ->
        error
    end
  end
end
