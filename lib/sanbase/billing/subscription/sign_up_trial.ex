defmodule Sanbase.Billing.Subscription.SignUpTrial do
  @moduledoc """
  Module for creating free trial and sending follow-up emails after user signs up.
  We send 6 types of emails in the span of the 14-day free trial:

  1. A welcome email - immediately post registration.
  2. An educational email on **day 4** of free trial.
  3. A second educational email on **day 7** of free trial
  4. An email with coupon **3 days before free trial ends**.
  5. An email to users with credit card **1 day before charging them**.
  6. An email to users without credit card when we cancel expired free trial.

  A cron job runs twice a day and makes sure to send email at the proper day of the user's trial.
  """
  use Ecto.Schema

  import Ecto.Changeset

  require Logger

  alias Sanbase.Auth.User
  alias Sanbase.Billing.Subscription.PromoTrial
  alias Sanbase.Repo
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.{Subscription, Product}

  @free_trial_days 14
  # Free trial plans are Sanbase PRO plans
  @free_trial_plans [Plan.Metadata.sanbase_pro()]

  @day_email_type_map %{
    4 => :sent_first_education_email,
    7 => :sent_second_education_email,
    13 => :sent_cc_will_be_charged
  }

  @templates %{
    # immediately after sign up
    sent_welcome_email: "sanbase-post-registration",
    # on the 4th day
    sent_first_education_email: "first-edu-email",
    # on the 7th day
    sent_second_education_email: "second-edu-email",
    # 3 days before end with coupon code
    sent_trial_will_end_email: "trial-three-days-before-end",
    # 1 day before end on customers with credit card
    sent_cc_will_be_charged: "trial-finished",
    # when we cancel - ~ 2 hours before end
    sent_trial_finished_without_cc: "trial-finished-without-card"
  }

  schema "sign_up_trials" do
    belongs_to(:user, User)
    belongs_to(:subscription, Subscription)

    field(:sent_welcome_email, :boolean, dafault: false)
    field(:sent_first_education_email, :boolean, dafault: false)
    field(:sent_second_education_email, :boolean, dafault: false)
    field(:sent_trial_will_end_email, :boolean, dafault: false)
    field(:sent_cc_will_be_charged, :boolean, dafault: false)
    field(:sent_trial_finished_without_cc, :boolean, dafault: false)

    timestamps()
  end

  @doc false
  def changeset(sign_up_trial, attrs) do
    sign_up_trial
    |> cast(attrs, [
      :user_id,
      :subscription_id,
      :sent_welcome_email,
      :sent_first_education_email,
      :sent_second_education_email,
      :sent_trial_will_end_email,
      :sent_cc_will_be_charged,
      :sent_trial_finished_without_cc
    ])
    |> validate_required([:user_id])
    |> unique_constraint(:user_id)
    |> unique_constraint(:subscription_id)
  end

  # schedule to run twice a day
  def run do
    __MODULE__
    |> Repo.all()
    |> Enum.each(fn sign_up_trial ->
      trial_day = calc_trial_day(sign_up_trial)

      case Map.get(@day_email_type_map, trial_day) do
        nil ->
          :ok

        email_type ->
          maybe_send_email(sign_up_trial, email_type)
      end
    end)
  end

  defp calc_trial_day(%__MODULE__{inserted_at: inserted_at}) do
    Timex.diff(Timex.now(), inserted_at, :days)
  end

  def by_user_id(user_id) do
    Repo.get_by(__MODULE__, user_id: user_id)
  end

  def create(user_id) do
    %__MODULE__{} |> changeset(%{user_id: user_id}) |> Repo.insert()
  end

  def update_trial(sign_up_trial, params) do
    sign_up_trial |> changeset(params) |> Repo.update()
  end

  def create_subscription(user_id) do
    with {:ok, sign_up_trial} <- create(user_id),
         {:ok, sign_up_trial} <- create_promo_trial(sign_up_trial) do
      send_email_async(sign_up_trial, :sent_welcome_email)

      {:ok, sign_up_trial}
    end
  end

  def handle_trial_will_end(stripe_subscription_id) do
    with {:ok, subscription} <- get_trialing_subscription(stripe_subscription_id),
         {:ok, sign_up_trial} <- get_sign_up_trial(subscription) do
      do_send_email_and_mark_sent(sign_up_trial, :sent_trial_will_end_email)
    end
  end

  def maybe_send_trial_finished_email(subscription) do
    Repo.get_by(__MODULE__, user_id: subscription.user_id, subscription_id: subscription.id)
    |> case do
      %__MODULE__{sent_trial_finished_without_cc: false} = sign_up_trial ->
        do_send_email_and_mark_sent(sign_up_trial, :sent_trial_finished_without_cc)

      _ ->
        :ok
    end
  end

  def send_email_async(%__MODULE__{} = sign_up_trial, email_type) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      do_send_email_and_mark_sent(sign_up_trial, email_type)
    end)
  end

  defp get_trialing_subscription(stripe_subscription_id) do
    Subscription.by_stripe_id(stripe_subscription_id)
    |> case do
      %Subscription{status: :trialing} = subscription ->
        {:ok, subscription}

      _ ->
        {:error, :no_trialing_subscription}
    end
  end

  defp get_sign_up_trial(subscription) do
    Repo.get_by(__MODULE__, user_id: subscription.user_id, subscription_id: subscription.id)
    |> case do
      %__MODULE__{sent_trial_will_end_email: false} = sign_up_trial ->
        {:ok, sign_up_trial}

      _ ->
        {:error, :no_sign_up_trial}
    end
  end

  defp create_promo_trial(%__MODULE__{user_id: user_id} = sign_up_trial) do
    user = Repo.get(User, user_id)

    PromoTrial.create_promo_trial(%{
      user_id: user_id,
      plans: @free_trial_plans,
      trial_days: @free_trial_days
    })
    |> case do
      {:ok, _} ->
        current_subscription = Subscription.current_subscription(user, Product.product_sanbase())
        update_trial(sign_up_trial, %{subscription_id: current_subscription.id})

      {:error, reason} ->
        {:error, reason}
    end
  end

  # this email is send only to users with credit card in Stripe
  defp maybe_send_email(sign_up_trial, :sent_cc_will_be_charged) do
    if User.has_credit_card_in_stripe?(sign_up_trial.user_id) do
      do_send_email_and_mark_sent(sign_up_trial, :sent_cc_will_be_charged)
    end
  end

  defp maybe_send_email(sign_up_trial, email_type)
       when email_type in [
              :sent_first_education_email,
              :sent_second_education_email
            ] do
    do_send_email_and_mark_sent(sign_up_trial, email_type)
  end

  defp do_send_email_and_mark_sent(%__MODULE__{user_id: user_id} = sign_up_trial, email_type) do
    user = Repo.get(User, user_id)
    template = @templates[email_type]

    # User exists, we have proper template in Mandrill and this email type is not already sent
    if user && template && !sign_up_trial[email_type] do
      Logger.info(
        "Trial email template #{template} sent to: #{user.email}, name=#{
          user.username || user.email
        }"
      )

      Sanbase.MandrillApi.send(template, user.email, %{name: user.username || user.email}, %{
        merge_language: "handlebars"
      })

      update_trial(sign_up_trial, %{email_type => true})
    end
  end
end
