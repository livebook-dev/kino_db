defmodule KinoDB.MixProject do
  use Mix.Project

  @version "0.1.1"
  @description "Databases integration with Livebook"

  def project do
    [
      app: :kino_db,
      version: @version,
      description: @description,
      name: "KinoDB",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [
      mod: {KinoDB.Application, []}
    ]
  end

  defp deps do
    [
      {:kino, "~> 0.6.1"},
      {:table, "~> 0.1.0"},
      {:postgrex, "~> 0.16.3 or ~> 0.17", optional: true},
      {:exqlite, "~> 0.11", optional: true},
      {:myxql, "~> 0.6.2 or ~> 0.7", optional: true},
      {:db_connection, "~> 2.4.2", optional: true},
      {:req_bigquery, github: "livebook-dev/req_bigquery", optional: true},
      {:req_athena, github: "livebook-dev/req_athena", optional: true},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "components",
      source_url: "https://github.com/livebook-dev/kino_db",
      source_ref: "v#{@version}",
      extras: ["guides/components.livemd"]
    ]
  end

  def package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/livebook-dev/kino_db"
      }
    ]
  end
end
