defmodule Kollective.Workers.WorkerHelper do
  alias Kollective.Config

  def worker_args(queue) do
    # 🔄 FIX: Use your true get/2 signature to fetch the workers configuration group
    case Config.get(:workers, :retries) do
      retries when is_map(retries) ->
        # If stored in the DB as a map, look up the queue atom or string key
        case Map.get(retries, queue) || Map.get(retries, Atom.to_string(queue)) do
          nil -> []
          max_attempts -> [max_attempts: max_attempts]
        end

      retries when is_list(retries) ->
        # If stored as a Keyword list fallback, look up via Keyword tools
        case Keyword.get(retries, queue) do
          nil -> []
          max_attempts -> [max_attempts: max_attempts]
        end

      _nil_or_invalid ->
        []
    end
  end

  def sidekiq_backoff(attempt, pow \\ 4, base_backoff \\ 15) do
    backoff =
      :math.pow(attempt, pow) +
        base_backoff +
        :rand.uniform(2 * base_backoff) * attempt

    trunc(backoff)
  end

  defmacro __using__(opts) do
    caller_module = __CALLER__.module
    queue = Keyword.fetch!(opts, :queue)

    quote do
      # Note: `max_attempts` is intended to be overridden in `new/2` call
      use Oban.Worker,
        queue: unquote(queue),
        max_attempts: 1

      alias Oban.Job
      alias Kollective.Workers.WorkerHelper

      def enqueue(op, params, worker_args \\ []) do
        params = Map.merge(%{"op" => op}, params)
        queue_atom = String.to_atom(unquote(queue))
        worker_args = worker_args ++ WorkerHelper.worker_args(queue_atom)

        unquote(caller_module)
        |> apply(:new, [params, worker_args])
        |> Oban.insert()
      end
    end
  end
end
