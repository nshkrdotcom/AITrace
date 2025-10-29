defmodule AITrace.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AITrace.Collector
    ]

    opts = [strategy: :one_for_one, name: AITrace.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
