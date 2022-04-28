defmodule KinoDB.ConnectionCellTest do
  use ExUnit.Case, async: true

  import KinoTest

  alias KinoDB.ConnectionCell

  setup :configure_livebook_bridge

  describe "initialization" do
    test "returns default source when started with missing attrs" do
      {_kino, source} = start_smart_cell!(ConnectionCell, %{"variable" => "conn"})

      assert source ==
               """
               opts = [hostname: "", port: 5432, username: "", password: "", database: ""]
               {:ok, conn} = Kino.start_child({Postgrex, opts})\
               """
    end

    test "restores source code from attrs" do
      attrs = %{
        "variable" => "db",
        "type" => "mysql",
        "hostname" => "localhost",
        "port" => 4444,
        "username" => "admin",
        "password" => "pass",
        "database" => "default"
      }

      {_kino, source} = start_smart_cell!(ConnectionCell, attrs)

      assert source ==
               """
               opts = [
                 hostname: "localhost",
                 port: 4444,
                 username: "admin",
                 password: "pass",
                 database: "default"
               ]

               {:ok, db} = Kino.start_child({MyXQL, opts})\
               """
    end
  end

  test "when a field changes, broadcasts the change and sends source update" do
    {kino, _source} = start_smart_cell!(ConnectionCell, %{"variable" => "conn"})

    push_event(kino, "update_field", %{"field" => "hostname", "value" => "localhost"})

    assert_broadcast_event(kino, "update", %{"fields" => %{"hostname" => "localhost"}})

    assert_smart_cell_update(kino, %{"hostname" => "localhost"}, """
    opts = [hostname: "localhost", port: 5432, username: "", password: "", database: ""]
    {:ok, conn} = Kino.start_child({Postgrex, opts})\
    """)
  end

  test "when an invalid variable name is set, restores the previous value" do
    {kino, _source} = start_smart_cell!(ConnectionCell, %{"variable" => "db"})

    push_event(kino, "update_field", %{"field" => "variable", "value" => "DB"})

    assert_broadcast_event(kino, "update", %{"fields" => %{"variable" => "db"}})
  end

  test "when the database type changes, restores the default port for that database" do
    {kino, _source} =
      start_smart_cell!(ConnectionCell, %{
        "variable" => "conn",
        "type" => "postgres",
        "port" => 5432
      })

    push_event(kino, "update_field", %{"field" => "type", "value" => "mysql"})

    assert_broadcast_event(kino, "update", %{"fields" => %{"type" => "mysql", "port" => 3306}})

    assert_smart_cell_update(kino, %{"type" => "mysql", "port" => 3306}, """
    opts = [hostname: "", port: 3306, username: "", password: "", database: ""]
    {:ok, conn} = Kino.start_child({MyXQL, opts})\
    """)
  end
end
