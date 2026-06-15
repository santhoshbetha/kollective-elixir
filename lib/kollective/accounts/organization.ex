defmodule Kollective.Accounts.Organization do
  use Kollective.Schemas.Schema

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :bio, :string
    field :is_verified, :boolean, default: false

    has_many :memberships, Kollective.Accounts.OrganizationMember
    has_many :members, through: [:memberships, :user]
    has_many :posts, Kollective.Posts.Post

    many_to_many :followers, Kollective.Accounts.User,
      join_through: "user_organization_relationships"

    # Organization Badges (e.g., "Local Verified Partner") provides visual trust and helps users
    # distinguish between standard news groups and official community partners. You can manage
    # this via an Admin-only flag in your database and display it as a specific UI treatment in React

    # 1. Add a badge_type field to the Organization schema to allow for different levels of partnership (e.g., verified, partner, premium).
    field :badge_type, Ecto.Enum, values: [:none, :verified, :partner], default: :none

    timestamps(type: :utc_datetime)
  end
end
