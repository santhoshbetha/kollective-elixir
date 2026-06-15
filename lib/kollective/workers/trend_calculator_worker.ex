# Use Oban to run a "recalculation" job every hour. This job looks at the last
# 24 hours of usage and updates the trending score.
defmodule Kollective.Workers.TrendCalculatorWorker do
  use Oban.Worker, queue: :default

  def perform(_job) do
    # 1. Sum up usage for the last 24 hours
    # 2. Compare against the weekly average
    # 3. Update a 'trending_score' on the Hashtag schema
    Kollective.Hashtags.Hashtags.update_all_trending_scores()
    :ok
  end
end
