defmodule SanbaseWeb.ExAdmin.Insight.Post do
  use ExAdmin.Register

  alias Sanbase.Insight.Post

  register_resource Sanbase.Insight.Post do
    create_changeset(:create_changeset)
    update_changeset(:update_changeset)
    action_items(only: [:show, :edit, :delete])

    index do
      column(:id)
      column(:title)
      column(:is_featured, &is_featured(&1))
      column(:is_pulse)
      column(:state)
      column(:ready_state)
      column(:moderation_comment)
      column(:user, link: true)
    end

    show post do
      attributes_table do
        row(:id)
        row(:title)
        row(:short_desc)
        row(:prediction)
        row(:is_featured, &is_featured(&1))
        row(:is_pulse)
        row(:is_paywall_required)
        row(:state)
        row(:ready_state)
        row(:moderation_comment)
        row(:user, link: true)

        row(:text)
      end

      panel "Metrics Used" do
        table_for Sanbase.Repo.preload(post, [:metrics]).metrics do
          column(:name, link: true)
        end
      end
    end

    form post do
      inputs do
        input(
          post,
          :is_featured,
          collection: ~w[true false],
          selected: true
        )

        input(
          post,
          :is_pulse,
          collection: ~w[true false],
          selected: true
        )

        input(
          post,
          :is_paywall_required,
          collection: ~w[true false],
          selected: true
        )

        input(
          post,
          :prediction
        )

        input(post, :state,
          collection: [
            Post.awaiting_approval_state(),
            Post.approved_state(),
            Post.declined_state()
          ]
        )

        input(post, :moderation_comment)
      end
    end

    controller do
      after_filter(:set_featured, only: [:update])
    end
  end

  defp is_featured(%Post{} = ut) do
    ut = Sanbase.Repo.preload(ut, [:featured_item])
    (ut.featured_item != nil) |> Atom.to_string()
  end

  def set_featured(conn, params, resource, :update) do
    case params.post.is_featured do
      str when str in ["true", "false"] ->
        is_featured = str |> String.to_existing_atom()
        Sanbase.FeaturedItem.update_item(resource, is_featured)

      nil ->
        :ok
    end

    {conn, params, resource}
  end
end
