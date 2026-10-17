defmodule Kollective.Repo.Migrations.AddPublicKeyToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # We use :text because PEM key blocks contain multiple string lines with linebreaks
      add :public_key, :text, null: true
    end
  end
end
