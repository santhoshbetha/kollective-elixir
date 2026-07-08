defmodule Kollective.Events.Comment do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  @statuses ["pending", "approved", "rejected"]

  schema "event_comments" do
    field :content, :string

    # Image support (S3/R2 URLs)
    field :image_url, :string

    # AI Moderation Status
    field :moderation_status, :string, default: "pending"

    # Relationships
    belongs_to :user, Kollective.Accounts.User
    belongs_to :event, Kollective.Events.Event

    # NEW: Self-referencing relationship for threads
    belongs_to :parent, __MODULE__
    has_many :replies, __MODULE__, foreign_key: :parent_id

    field :likes_count, :integer, virtual: true, default: 0

    timestamps()
  end

  @doc "Main changeset for creating a comment"
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:content, :image_url, :user_id, :event_id, :moderation_status, :parent_id])
    # Allow text to be blank if uploading pure images
    |> validate_required([:user_id, :event_id])
    # Ensures a comment isn't empty
    |> validate_content_or_image()
    |> validate_inclusion(:moderation_status, @statuses)
    |> validate_length(:content, max: 5000)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:event_id)
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

# Why this is the "Golden Path":

#  Polymorphic Content: The validate_content_or_image check allows users to post "Image only" comments (like a photo from the event) or "Text only" comments.
#  Database Integrity: Using on_delete: :delete_all ensures that if an Event is cancelled or a User deletes their account, the chat history is scrubbed automatically.
#  Performance: The composite index on [:event_id, :inserted_at] makes your TanStack Virtual infinite scroll lightning fast even with millions of rows.
#  Safety: Defaulting moderation_status to pending ensures your Moderation Worker always has a starting point.

# Why this is the "Golden Path":

# Polymorphic Content: The validate_content_or_image check allows users to post "Image only" comments (like a photo from the event) or "Text only" comments.
# Database Integrity: Using on_delete: :delete_all ensures that if an Event is cancelled or a User deletes their account, the chat history is scrubbed automatically.
# Performance: The composite index on [:event_id, :inserted_at] makes your TanStack Virtual infinite scroll lightning fast even with millions of rows.
# Safety: Defaulting moderation_status to pending ensures your Moderation Worker always has a starting point.
