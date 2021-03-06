defmodule SanbaseWeb.Graphql.CommentTypes do
  use Absinthe.Schema.Notation

  import Absinthe.Resolution.Helpers
  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.{
    InsightResolver,
    TimelineEventResolver
  }

  alias SanbaseWeb.Graphql.SanbaseRepo

  enum :comment_entity_enum do
    value(:insight)
    value(:timeline_event)
  end

  object :comment do
    field(:id, non_null(:id))

    field :insight_id, non_null(:id) do
      cache_resolve(&InsightResolver.insight_id/3)
    end

    field :timeline_event_id, non_null(:id) do
      cache_resolve(&TimelineEventResolver.timeline_event_id/3)
    end

    field(:content, non_null(:string))
    field(:user, non_null(:public_user), resolve: dataloader(SanbaseRepo))
    field(:parent_id, :id)
    field(:root_parent_id, :id)
    field(:subcomments_count, :integer)
    field(:inserted_at, non_null(:datetime))
    field(:edited_at, :datetime)
  end
end
