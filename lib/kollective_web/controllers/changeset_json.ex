# Handling the Error Response in your React catch block so it displays the specific validation messages (like "Content too long")
# To handle errors properly in your React app, you need to ensure your Phoenix backend serializes
# Ecto changeset errors into a readable JSON format and that your React frontend can parse those messages to display them to the user.

#Ensure your ChangesetJSON looks like this to make messages human-readable by replacing placeholders like %{count} with actual values

defmodule KollectiveWeb.ChangesetJSON do
  def error(%{changeset: changeset}) do
    # Converts %{content: [{"should be %{count} chars", [count: 500]}]}
    # into %{content: ["should be 500 chars"]}
    %{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
