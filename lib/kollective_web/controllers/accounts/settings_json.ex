defmodule KollectiveWeb.SettingsJSON do
  # 💡 Defines how to convert data targets into clean JSON payloads for React
  def edit(%{user: user}) do
    %{
      status: "success",
      data: %{
        user: %{
          id: user.id,
          email: user.email,
          username: user.username,
          display_name: user.display_name,
          locale: user.locale
        }
      }
    }
  end
end
