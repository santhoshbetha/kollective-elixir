defmodule Kollective.Businesses.Upvote do
  use Kollective.Schemas.Schema

  @primary_key false
  schema "business_upvotes" do
    belongs_to :user, Kollective.Accounts.User, primary_key: true
    belongs_to :business, Kollective.Businesses.Business, primary_key: true

    timestamps()
  end
end
