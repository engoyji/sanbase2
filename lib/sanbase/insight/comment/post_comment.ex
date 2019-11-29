defmodule Sanbase.Insight.PostComment do
  @moduledoc ~s"""
  """
  use Ecto.Schema

  import Ecto.{Query, Changeset}

  alias Sanbase.Insight.{Post, Comment}

  schema "post_comments_mapping" do
    belongs_to(:comment, Comment)
    belongs_to(:post, Post)

    timestamps()
  end

  def changeset(%__MODULE__{} = mapping, attrs \\ %{}) do
    mapping
    |> cast(attrs, [:post_id, :comment_id])
    |> validate_required([:post_id, :comment_id])
    |> unique_constraint(:comment_id)
  end

  def create_and_link(post_id, user_id, parent_id, content) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(
      :create_comment,
      fn _changes -> Comment.create(user_id, content, parent_id) end
    )
    |> Ecto.Multi.run(:link_comment_and_post, fn
      %{create_comment: comment} ->
        link(comment.id, post_id)
    end)
    |> Sanbase.Repo.transaction()
  end

  def link(comment_id, post_id) do
    %__MODULE__{}
    |> changeset(%{comment_id: comment_id, post_id: post_id})
    |> Sanbase.Repo.insert()
  end

  def get_comments(post_id, %{cursor: cursor, limit: limit}) do
    post_comments_query(post_id)
    |> apply_cursor(cursor)
    |> order_by([c], c.inserted_at)
    |> limit(^limit)
    |> Sanbase.Repo.all()
  end

  defp post_comments_query(post_id) do
    from(p in __MODULE__,
      where: p.post_id == ^post_id,
      preload: [:comment, comment: :user]
    )
  end

  defp apply_cursor(query, %{type: :before, before: datetime}) do
    from(
      c in query,
      where: c.inserted_at < ^datetime
    )
  end

  defp apply_cursor(query, %{type: :after, after: datetime}) do
    from(
      c in query,
      where: c.inserted_at >= ^datetime
    )
  end
end
