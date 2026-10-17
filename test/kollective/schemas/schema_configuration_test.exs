# test/kollective/schemas/schema_configuration_test.exs
defmodule Kollective.Schemas.SchemaConfigurationTest do
  use Kollective.DataCase, async: true

  # Dynamic compilation scan to discover all schema modules starting with Kollective
  @all_schemas :code.all_available()
               |> Stream.map(fn {module_name, _, _} ->
                 Module.concat([List.to_string(module_name)])
               end)
               |> Stream.filter(fn module ->
                 String.starts_with?(inspect(module), "Kollective.") and
                   Code.ensure_loaded?(module) and
                   function_exported?(module, :__schema__, 1)
               end)
               # Exclude abstract base schemas and custom string key config schemas
               |> Stream.reject(fn module ->
                 module in [
                   Kollective.Schemas.Schema,
                   Kollective.Admins.FeatureFlag,
                   Kollective.Moderation.SovereignOperator
                 ]
               end)
               |> Enum.to_list()

  describe "universal ULID enforcement" do
    test "ensures primary keys are explicitly mapped to Ecto.ULID" do
      assert @all_schemas != [], "Schema discovery failed. No schemas were detected."

      for schema <- @all_schemas do
        # Use a case statement to safely handle schemas with no primary key
        case schema.__schema__(:primary_key) do
          [] ->
            # Skips join tables or embedded schemas without failing
            :ok

          [pk_field] ->
            pk_type = schema.__schema__(:type, pk_field)

            assert pk_type == Ecto.ULID,
                   "Expected #{inspect(schema)} primary key to be Ecto.ULID, but got #{inspect(pk_type)}. Check if @primary_key was overwritten inside the schema file."

          _composite_keys ->
            # Handles composite keys if you have join tables with multiple primary keys
            :ok
        end
      end
    end

    test "ensures timestamps are globally forced to :utc_datetime" do
      for schema <- @all_schemas do
        if :inserted_at in schema.__schema__(:fields) do
          assert schema.__schema__(:type, :inserted_at) == :utc_datetime,
                 "Expected #{inspect(schema)} :inserted_at to be :utc_datetime"
        end

        if :updated_at in schema.__schema__(:fields) do
          assert schema.__schema__(:type, :updated_at) == :utc_datetime,
                 "Expected #{inspect(schema)} :updated_at to be :utc_datetime"
        end
      end
    end

    test "ensures all belongs_to associations enforce Ecto.ULID foreign keys" do
      for schema <- @all_schemas do
        # 1. Fetch all association names defined on the schema (e.g., [:user, :organization])
        for assoc_name <- schema.__schema__(:associations) do
          # 2. Extract metadata configuration for each specific association
          assoc_meta = schema.__schema__(:association, assoc_name)

          # 3. Filter specifically for belongs_to (has_many/has_one do not hold foreign keys)
          if assoc_meta.__struct__ == Ecto.Association.BelongsTo do
            fk_field = assoc_meta.owner_key
            fk_type = schema.__schema__(:type, fk_field)

            assert fk_type == Ecto.ULID, """
            Foreign key mismatch found in #{inspect(schema)}:
            The association :#{assoc_name} uses foreign key :#{fk_field}.
            Expected type to be Ecto.ULID, but got #{inspect(fk_type)}.
            Ensure you are using `use Kollective.Schemas.Schema` and did not overwrite @foreign_key_type.
            """
          end
        end
      end
    end
  end
end
