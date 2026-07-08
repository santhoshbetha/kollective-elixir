# lib/my_app/moderation/restricted_keyword.ex
defmodule Kollective.Moderation.RestrictedKeyword do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "restricted_keywords" do
    field :word, :string
    field :is_active, :boolean, default: true
    # Options: pending, reject
    field :action, :string, default: "pending"

    # levels: "soft" (pending) or "hard" (reject/delete)
    # Auto-Reject, you need to differentiate between "Soft Banned" words
    # (which trigger a Review status) and "Hard Banned" words (which trigger an immediate rejection or deletion)
    field :level, :string, default: "soft"

    # Default weight of 1. Rare/severe words can have higher weights.
    # Keyword Weighting
    field :weight, :integer, default: 1

    # If NULL, the keyword lasts forever. If set, it expires.
    # Keyword Expiry
    field :expires_at, :utc_datetime

    timestamps()
  end

  @doc "Validates keyword entries before saving"
  def changeset(keyword, attrs) do
    keyword
    |> cast(attrs, [:word, :is_active, :action, :level, :weight, :expires_at])
    |> validate_required([:word, :level])
    |> validate_inclusion(:action, ["pending", "reject"])
    |> validate_inclusion(:level, ["soft", "hard"])
    |> unique_constraint(:word)
    # Normalize to lowercase
    |> update_change(:word, &String.downcase/1)
  end
end

# create unique_index(:restricted_keywords, [:word])
