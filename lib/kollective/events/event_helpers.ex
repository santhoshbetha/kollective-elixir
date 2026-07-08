# 2. For Calendar Invites/Emails (The "Logic" Way)
# If you need this for generating .ics files or sending emails (where there is no React frontend involved),
# put it in a Helper module inside your Events context.

# if you are building the .ics download feature we discussed earlier.

defmodule Kollective.Events.EventHelpers do
  # Update these with your real CDN or R2 storage public URLs
  @default_banners [
    "https://r2.dev",
    "https://r2.dev",
    "https://r2.dev"
  ]

  @doc """
  Converts UTC start time to the event's local string format.
  Perfect for email notification templates or server logs.
  """
  def local_time_string(%{start_time: %DateTime{} = start_time, timezone: timezone}) do
    start_time
    # Uses application default timezone database configured in config.exs
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%Y-%m-%d %I:%M %p")
  end

  def local_time_string(_), do: "Time unconfigured"

  @doc """
  Formats a DateTime into an iCal-compliant string: 20261025T143000.
  It shifts to the target zone first to match the TZID scope inside an .ics file.
  """
  def format_ical_datetime(%DateTime{} = datetime, timezone \\ "Etc/UTC") do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%Y%m%dT%H%M%S")
  rescue
    # Fallback to standard UTC marker string formatting if timezone parsing fails
    _error -> Calendar.strftime(datetime, "%Y%m%dT%H%M%SZ")
  end

  @doc """
  Resolves the public image path for an event banner.
  Consistently maps ELID/String tokens to the same placeholder index safely.
  """
  def get_banner_url(%{banner_url: nil, id: elid_str}) when is_binary(elid_str) do
    total_banners = Enum.count(@default_banners)

    # :erlang.phash2 handles any Elixir term/binary string instantly
    # It returns a deterministic integer from 0 up to (total_banners - 1)
    index = :erlang.phash2(elid_str, total_banners)

    Enum.at(@default_banners, index)
  end

  # Fallback catch-all clauses for model parsing safety
  def get_banner_url(%{banner_url: url}) when is_binary(url), do: url
  def get_banner_url(_), do: Enum.at(@default_banners, 0)
end
