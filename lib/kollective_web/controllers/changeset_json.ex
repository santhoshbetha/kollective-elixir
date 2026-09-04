# Handling the Error Response in your React catch block so it displays the specific validation messages (like "Content too long")
# To handle errors properly in your React app, you need to ensure your Phoenix backend serializes
# Ecto changeset errors into a readable JSON format and that your React frontend can parse those messages to display them to the user.

# Ensure your ChangesetJSON looks like this to make messages human-readable by replacing placeholders like %{count} with actual values

defmodule KollectiveWeb.ChangesetJSON do
  def error(%{changeset: changeset}) do
    # Converts %{content: [{"should be %{count} chars", [count: 500]}]}
    # into %{content: ["should be 500 chars"]}
    %{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  def translate_error({msg, opts}) do
    # If Gettext is loaded in your system architecture, it replaces strings natively
    if Code.ensure_loaded?(KollectiveWeb.Gettext) do
      # Handles pluralization interpolations automatically
      case opts[:count] do
        nil -> Gettext.dgettext(KollectiveWeb.Gettext, "errors", msg, opts)
        count -> Gettext.dngettext(KollectiveWeb.Gettext, "errors", msg, msg, count, opts)
      end
    else
      # Fallback to your exact reference implementation loop if Gettext is absent
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end
  end
end
