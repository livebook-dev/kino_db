defmodule KinoDB.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Kino.SmartCell.register(KinoDB.ConnectionCell)
    Kino.SmartCell.register(KinoDB.SQLCell)

    children = []
    opts = [strategy: :one_for_one, name: KinoDB.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
