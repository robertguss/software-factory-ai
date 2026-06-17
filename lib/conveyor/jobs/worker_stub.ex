defmodule Conveyor.Jobs.WorkerStub do
  @moduledoc false

  defmacro __using__(opts) do
    queue = Keyword.fetch!(opts, :queue)

    quote do
      use Oban.Worker, queue: unquote(queue), max_attempts: 1

      @impl Oban.Worker
      def perform(%Oban.Job{}) do
        :ok
      end
    end
  end
end
