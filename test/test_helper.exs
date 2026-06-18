ExUnit.configure(exclude: [live_agent: true])
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Conveyor.Repo, :manual)
