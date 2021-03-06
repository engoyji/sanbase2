defmodule SanbaseWeb.Graphql.Resolvers.ReportResolver do
  require Logger

  alias Sanbase.Report
  alias Sanbase.Billing.{Subscription, Product}

  @product_sanbase Product.product_sanbase()

  def upload_report(_root, %{report: report} = args, _resolution) do
    {params, _} = Map.split(args, [:name, :description])

    case Report.save_report(report, params) do
      {:ok, report} -> {:ok, report}
      {:error, _reason} -> {:error, "Can't save report!"}
    end
  end

  def get_reports(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    reports =
      Subscription.current_subscription(user, @product_sanbase)
      |> Subscription.plan_name()
      |> Report.get_published_reports()

    {:ok, reports}
  end

  def get_reports_by_tags(_root, %{tags: tags}, %{context: %{auth: %{current_user: user}}}) do
    plan =
      Subscription.current_subscription(user, @product_sanbase)
      |> Subscription.plan_name()

    reports = Report.get_by_tags(tags, plan)

    {:ok, reports}
  end
end
