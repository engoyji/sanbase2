defmodule SanbaseWeb.Graphql.EtherbiTypes do
  use Absinthe.Schema.Notation

  object :burn_rate_data do
    field(:datetime, non_null(:datetime))
    field(:burn_rate, :decimal)
  end

  object :transaction_volume do
    field(:datetime, non_null(:datetime))
    field(:transaction_volume, :decimal)
  end

  object :wallet do
    field(:name, non_null(:string))
    field(:address, non_null(:string))
  end
end
