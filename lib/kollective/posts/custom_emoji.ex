# Custom Emojis for your admins to upload, you need a dedicated schema for the emoji metadata and a
# secure upload strategy (using Phoenix LiveView or a standard API) to send files to your Cloudflare R2 bucket.

# Following the Mastodon standard, you store the shortcode (used in text like :elixir:) and the URLs
# for both the animated and static versions.
defmodule Kollective.Posts.CustomEmoji do
  use Kollective.Schemas.Schema
  import Ecto.Changeset

  schema "custom_emojis" do
    # e.g., "elixir"
    field :shortcode, :string
    # URL to the image on R2
    field :url, :string

    # Static preview image (the first frame) to show by
    # Static version (for accessibility/performance)
    field :static_url, :string

    # Grouping in the emoji picker
    field :category, :string
    field :visible_in_picker, :boolean, default: true

    timestamps()
  end

  def changeset(emoji, attrs) do
    emoji
    |> cast(attrs, [:shortcode, :url, :static_url, :category, :visible_in_picker])
    |> validate_required([:shortcode, :url])
    # Mastodon-style naming
    |> validate_format(:shortcode, ~r/^[a-z0-9_]+$/i)
    |> unique_constraint(:shortcode)
  end
end
