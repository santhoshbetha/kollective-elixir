defmodule Kollective.Media.WaffleEctoDefinition do
  @moduledoc """
  Enhanced Waffle Ecto definition wrapper supporting string defaults and asset URL strings.
  """

  defmacro __using__(_options) do
    definition = __CALLER__.module

    quote do
      defmodule Module.concat(unquote(definition), "Type") do
        if macro_exported?(Ecto.Type, :__using__, 1) do
          use Ecto.Type
        else
          @behaviour Ecto.Type
        end

        def type, do: Waffle.Ecto.Type.type()

        def cast(value) when is_binary(value), do: {:ok, value}
        def cast(%{file_name: _} = value), do: {:ok, value}
        def cast(value), do: Waffle.Ecto.Type.cast(unquote(definition), value)

        def load(value), do: Waffle.Ecto.Type.load(unquote(definition), value)

        def dump(value) when is_binary(value), do: {:ok, value}
        def dump(value), do: Waffle.Ecto.Type.dump(unquote(definition), value)
      end

      def url({%{file_name: file_name, updated_at: updated_at}, scope}, version, options)
          when is_binary(file_name) do
        if String.starts_with?(file_name, ["http://", "https://", "/"]) do
          file_name
        else
          url = super({file_name, scope}, version, options)

          if options[:signed] do
            url
          else
            case {url, updated_at} do
              {nil, _} ->
                nil

              {_, %NaiveDateTime{}} ->
                version_url(updated_at, url)

              {_, string} when is_bitstring(updated_at) ->
                version_url(NaiveDateTime.from_iso8601!(string), url)

              _ ->
                url
            end
          end
        end
      end

      def url({%{"file_name" => file_name, "updated_at" => updated_at}, scope}, version, options)
          when is_binary(file_name) do
        if String.starts_with?(file_name, ["http://", "https://", "/"]) do
          file_name
        else
          url = super({file_name, scope}, version, options)

          if options[:signed] do
            url
          else
            case {url, updated_at} do
              {nil, _} ->
                nil

              {_, %NaiveDateTime{}} ->
                version_url(updated_at, url)

              {_, string} when is_bitstring(updated_at) ->
                version_url(NaiveDateTime.from_iso8601!(string), url)

              _ ->
                url
            end
          end
        end
      end

      def url({%{file_name: file_name}, scope}, version, options) when is_binary(file_name) do
        if String.starts_with?(file_name, ["http://", "https://", "/"]) do
          file_name
        else
          super({file_name, scope}, version, options)
        end
      end

      def url({%{"file_name" => file_name}, scope}, version, options) when is_binary(file_name) do
        if String.starts_with?(file_name, ["http://", "https://", "/"]) do
          file_name
        else
          super({file_name, scope}, version, options)
        end
      end

      def url({file_name, scope}, version, options) when is_binary(file_name) do
        if String.starts_with?(file_name, ["http://", "https://", "/"]) do
          file_name
        else
          super({file_name, scope}, version, options)
        end
      end

      def delete({%{file_name: file_name, updated_at: _updated_at}, scope}),
        do: super({file_name, scope})

      def delete(args), do: super(args)

      defp version_url(updated_at, url) do
        stamp = :calendar.datetime_to_gregorian_seconds(NaiveDateTime.to_erl(updated_at))

        case URI.parse(url).query do
          nil -> url <> "?v=#{stamp}"
          _ -> url <> "&v=#{stamp}"
        end
      end
    end
  end
end
