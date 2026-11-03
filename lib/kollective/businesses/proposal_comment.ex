# lib/kollective/businesses/proposal_comment.ex
defmodule Kollective.Businesses.ProposalComment do
  @moduledoc """
  Threaded discussion message attached to a Business Proposal node.

  Mirrors the `Kollective.Events.Comment` (event_comments) thread layout:
  top-level discussion rows plus self-referencing `parent_id` replies, optional
  R2-hosted image attachments, and an AI moderation gate.
  """
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  @statuses ["pending", "approved", "rejected"]

  schema "proposal_comments" do
    field(:content, :string)
    field(:image_url, :string)
    field(:moderation_status, :string, default: "pending")

    belongs_to(:user, Kollective.Accounts.User)
    belongs_to(:business, Kollective.Businesses.Business, foreign_key: :business_id)

    # Self-referencing relationship for threads
    belongs_to(:parent, __MODULE__)
    has_many(:replies, __MODULE__, foreign_key: :parent_id)

    timestamps()
  end

  @doc "Main changeset for creating a proposal discussion comment"
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [
      :content,
      :image_url,
      :user_id,
      :business_id,
      :moderation_status,
      :parent_id
    ])
    # Allow text to be blank when uploading a pure image attachment
    |> validate_required([:user_id, :business_id])
    |> validate_content_or_image()
    |> validate_inclusion(:moderation_status, @statuses)
    |> validate_length(:content, max: 5000)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:business_id)
    |> foreign_key_constraint(:parent_id)
  end

  # Custom validation: Must have either text OR an image
  defp validate_content_or_image(changeset) do
    content = get_field(changeset, :content)
    image_url = get_field(changeset, :image_url)

    if is_nil(content) and is_nil(image_url) do
      add_error(changeset, :content, "Comment cannot be empty")
    else
      changeset
    end
  end
end
