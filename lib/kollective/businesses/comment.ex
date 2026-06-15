defmodule Kollective.Businesses.Comment do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "business_comments" do
    field :content, :string

    # Threaded replies support
    belongs_to :parent, __MODULE__
    has_many :replies, __MODULE__, foreign_key: :parent_id

    belongs_to :user, Kollective.Accounts.User
    belongs_to :business, Kollective.Businesses.Business

    timestamps()
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:content, :user_id, :business_id, :parent_id])
    |> validate_required([:content, :user_id, :business_id])
    |> validate_length(:content, max: 500)
  end
end
