defmodule AITrace.ReplayEngine do
  @moduledoc """
  Deterministic replay execution against past AITrace traces.
  """

  alias AITrace.ReplayContracts
  alias AITrace.ReplayEngine.{LineageReplayRunner, RequestRunner}

  @spec replay(map() | ReplayContracts.ReplayRequest.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def replay(request_or_attrs, opts \\ []) when is_list(opts) do
    RequestRunner.replay(request_or_attrs, opts)
  end

  @spec replay_lineage_events([map() | ReplayContracts.LineageReplayEvent.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def replay_lineage_events(events, opts \\ [])

  def replay_lineage_events(events, opts) when is_list(events) and is_list(opts) do
    LineageReplayRunner.replay(events, opts)
  end

  def replay_lineage_events(_events, _opts), do: {:error, :invalid_lineage_replay_events}
end
