# lib/kollective_web/controllers/user_json.ex
defmodule KollectiveWeb.UserJSON do
  def show(%{user: user}) do
    %{data: data(user)}
  end

  # {
  #  "user": {
  #    "username": "voter_123",
  #    "districts": {
  #      "l1": "01H7X... (National ID)",
  #      "l2": "01H8Y... (State ID)",
  #      "l3": "01H9Z... (Local ID)"
  #    },
  #    "district_names": {
  #      "l1": "Mumbai South",
  #      "l2": "Maharashtra Upper",
  #      "l3": "Colaba"
  #    }
  #  }
  # }
  def data(user) do
    %{
      id: user.id,
      username: user.username,
      email: user.email,

      # POLITICAL IDS (For API Calls)
      districts: %{
        l1: user.district_l1_id,
        l2: user.district_l2_id,
        l3: user.district_l3_id
      },

      # READABLE NAMES (For UI Labels/Breadcrumbs)
      district_names: %{
        l1: (user.district_l1 && user.district_l1.name) || "National",
        l2: (user.district_l2 && user.district_l2.name) || "State",
        l3: (user.district_l3 && user.district_l3.name) || "Local"
      },

      # GEOGRAPHY
      city: if(user.origin_city, do: user.origin_city.name),
      state_code: user.state,
      country_code: user.country,
      settings: %{
        auto_play_gifs: user.auto_play_gifs
      }
    }
  end
end
