defmodule Kollective.Hashtags.HashtagObject do
  use Kollective.Schemas.Schema

  # import Ecto.Changeset

  schema "hashtag_objects" do
    field(:hashtag_id, :id, primary_key: true)

    timestamps()
  end
end
