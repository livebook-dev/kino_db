defmodule KinoDB.ConnectionCellTest do
  use ExUnit.Case, async: true

  import Kino.Test

  alias KinoDB.ConnectionCell

  setup :configure_livebook_bridge

  describe "initialization" do
    test "returns default source when started with missing attrs" do
      {_kino, source} = start_smart_cell!(ConnectionCell, %{"variable" => "conn"})

      assert source ==
               """
               opts = [hostname: "localhost", port: 5432, username: "", password: "", database: ""]
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

    test "restores source code from attrs with SQLite3" do
      attrs = %{
        "variable" => "db",
        "type" => "sqlite",
        "database_path" => "/path/to/sqlite3.db"
      }

      {_kino, source} = start_smart_cell!(ConnectionCell, attrs)

      assert source ==
               """
               opts = [database: "/path/to/sqlite3.db"]
               {:ok, db} = Kino.start_child({Exqlite, opts})\
               """
    end

    test "restores source code from attrs with BigQuery" do
      attrs = %{
        "variable" => "db",
        "type" => "bigquery",
        "project_id" => "foo",
        "credentials" => %{},
        "default_dataset_id" => ""
      }

      {_kino, source} = start_smart_cell!(ConnectionCell, attrs)

      assert source ==
               """
               opts = [name: ReqBigQuery.Goth, http_client: &Req.request/1]
               {:ok, _pid} = Kino.start_child({Goth, opts})

               db =
                 Req.new(http_errors: :raise)
                 |> ReqBigQuery.attach(goth: ReqBigQuery.Goth, project_id: "foo", default_dataset_id: "")

               :ok\
               """

      credentials = %{
        "private_key" => "foo",
        "client_email" => "alice@example.com",
        "token_uri" => "/",
        "type" => "service_account"
      }

      {_kino, source} =
        start_smart_cell!(ConnectionCell, put_in(attrs["credentials"], credentials))

      assert source ==
               """
               credentials = %{
                 "client_email" => "alice@example.com",
                 "private_key" => "foo",
                 "token_uri" => "/",
                 "type" => "service_account"
               }

               opts = [
                 name: ReqBigQuery.Goth,
                 http_client: &Req.request/1,
                 source: {:service_account, credentials}
               ]

               {:ok, _pid} = Kino.start_child({Goth, opts})

               db =
                 Req.new(http_errors: :raise)
                 |> ReqBigQuery.attach(goth: ReqBigQuery.Goth, project_id: "foo", default_dataset_id: "")

               :ok\
               """

      credentials = %{
        "refresh_token" => "foo",
        "client_id" => "alice@example.com",
        "client_secret" => "bar",
        "type" => "authorized_user"
      }

      {_kino, source} =
        start_smart_cell!(ConnectionCell, put_in(attrs["credentials"], credentials))

      assert source ==
               """
               credentials = %{
                 "client_id" => "alice@example.com",
                 "client_secret" => "bar",
                 "refresh_token" => "foo",
                 "type" => "authorized_user"
               }

               opts = [
                 name: ReqBigQuery.Goth,
                 http_client: &Req.request/1,
                 source: {:refresh_token, credentials}
               ]

               {:ok, _pid} = Kino.start_child({Goth, opts})

               db =
                 Req.new(http_errors: :raise)
                 |> ReqBigQuery.attach(goth: ReqBigQuery.Goth, project_id: "foo", default_dataset_id: "")

               :ok\
               """
    end

    test "restores source code from attrs with Athena" do
      attrs = %{
        "variable" => "db",
        "type" => "athena",
        "access_key_id" => "id",
        "secret_access_key" => "secret",
        "region" => "region",
        "database" => "default",
        "output_location" => "s3://my-bucket"
      }

      {_kino, source} = start_smart_cell!(ConnectionCell, attrs)

      assert source ==
               """
               db =
                 Req.new(http_errors: :raise)
                 |> ReqAthena.attach(
                   access_key_id: "id",
                   secret_access_key: "secret",
                   region: "region",
                   database: "default",
                   output_location: "s3://my-bucket"
                 )

               :ok\
               """
    end

    test "doesn't restore source code with empty required fields" do
      attrs = %{
        "variable" => "db",
        "type" => "mysql",
        "hostname" => "",
        "port" => nil,
        "username" => "admin",
        "password" => "pass",
        "database" => "default"
      }

      {_kino, source} = start_smart_cell!(ConnectionCell, attrs)

      assert source == ""
    end
  end

  test "when a field changes, broadcasts the change and sends source update" do
    {kino, _source} = start_smart_cell!(ConnectionCell, %{"variable" => "conn"})

    push_event(kino, "update_field", %{"field" => "hostname", "value" => "myhost"})

    assert_broadcast_event(kino, "update", %{"fields" => %{"hostname" => "myhost"}})

    assert_smart_cell_update(kino, %{"hostname" => "myhost"}, """
    opts = [hostname: "myhost", port: 5432, username: "", password: "", database: ""]
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
    opts = [hostname: "localhost", port: 3306, username: "", password: "", database: ""]
    {:ok, conn} = Kino.start_child({MyXQL, opts})\
    """)
  end
end
