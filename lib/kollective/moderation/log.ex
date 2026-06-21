#Audit Log that records every moderation action (who approved what and when)
defmodule Kollective.Moderation.Log do
  use Ecto.Schema
  import Ecto.Changeset

  schema "moderation_logs" do
    field :action, :string
    field :reason, :string
    field :notes, :string
    belongs_to :admin, Kollective.Accounts.User
    belongs_to :post, Kollective.Posts.Post

    timestamps()
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [:action, :reason, :notes, :admin_id, :post_id])
    |> validate_required([:action, :admin_id, :post_id])
  end
end
