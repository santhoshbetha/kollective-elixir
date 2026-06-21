# The Reporter Leaderboard (Admin API)
# This allows admins to see who their most helpful "community moderators" are.

#Why this is a "Self-Cleaning" System:

#    Discourages Trolls: If a user tries to harass a "Verified" member by reporting all their posts, their report_trust_score will plummet to
#    after a few admin dismissals, making their future reports effectively useless.
#    Incentivizes Accuracy: Users want a higher score to feel their voice has weight.
#    Identifies Future Moderators: Users at the top of the Leaderboard with
#    trust scores and
#    false reports are your best candidates for Exempt/Power User status.

defmodule Kollective.Moderation.Leaderboard do
  import Ecto.Query
  alias Kollective.{Repo, Accounts.User}

  def get_top_reporters(limit \\ 10) do
    from(u in User,
      where: u.successful_reports_count > 0,
      order_by: [desc: u.report_trust_score, desc: u.successful_reports_count],
      limit: ^limit,
      select: %{
        id: u.id,
        username: u.username,
        score: u.report_trust_score,
        successful: u.successful_reports_count,
        false: u.false_reports_count
      }
    )
    |> Repo.all()
  end
end
