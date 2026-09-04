# lib/kollective/workers/pipeline_worker.ex
defmodule Kollective.Workers.PipelineWorker do
  @moduledoc """
  Autonomous execution background ledger engine.
  Processes vote tallies and advances high-performing candidates between flow stages.
  """
  import Ecto.Query
  alias Kollective.Repo
  alias Kollective.Videos.CandidateVideo

  @doc """
  Executes an escalation evaluation across all active municipal and high position tracks.
  Designed to be invoked nightly via Quantum CRON or an isolated Phoenix Task tree.
  """
  def evaluate_and_escalate_all do
    Repo.transaction(fn ->
      # 🏙️ 1. ESCALATE FLOW B: Advance top candidates from Neighborhood Booth blocks to Ward levels
      # Grabs the top candidate per polling booth and moves them into the broader ward primary
      query_booth =
        from v in CandidateVideo,
          where: v.office_level == "municipal" and v.visibility_stage == "booth",
          order_by: [desc: v.votes_count]

      # Run database loops and switch phase keys smoothly [A]
      Repo.all(query_booth)
      |> Enum.group_by(& &1.polling_booth_id)
      |> Enum.each(fn {_booth_id, pitches} ->
        # Advance only the single top-voted candidate from this neighborhood booth block
        case Enum.at(pitches, 0) do
          nil ->
            :ok

          top_pitch ->
            top_pitch
            |> Ecto.Changeset.change(%{visibility_stage: "ward"})
            |> Repo.update!()
        end
      end)

      # 🏛️ 2. ESCALATE FLOW A: Advance high office candidates from sub-districts to public slates
      query_high =
        from v in CandidateVideo,
          where:
            v.office_level in ["congress", "state_senate"] and
              v.visibility_stage == "sub_district_primary",
          order_by: [desc: v.votes_count]

      Repo.all(query_high)
      |> Enum.group_by(& &1.sub_district)
      |> Enum.each(fn {_sub_id, pitches} ->
        # Advance top candidates to the final district slate tracker dashboard view
        pitches
        # Take top 3 consensus candidates per sub-district zone
        |> Enum.take(3)
        |> Enum.each(fn pitch ->
          pitch
          |> Ecto.Changeset.change(%{visibility_stage: "public_slate"})
          |> Repo.update!()
        end)
      end)
    end)
  end
end
