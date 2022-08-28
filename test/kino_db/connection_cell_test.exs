defmodule KinoDB.ConnectionCellTest do
  use ExUnit.Case, async: true

  import Kino.Test

  alias KinoDB.ConnectionCell

  setup :configure_livebook_bridge

  @attrs %{
    "variable" => "db",
    "type" => "postgres",
    "hostname" => "localhost",
    "port" => 4444,
    "username" => "admin",
    "password" => "pass",
    "use_password_secret" => false,
    "password_secret" => "",
    "database" => "default",
    "database_path" => "/path/to/sqlite3.db",
    "project_id" => "foo",
    "credentials" => %{},
    "default_dataset_id" => "",
    "access_key_id" => "id",
    "secret_access_key" => "secret",
    "token" => "token",
    "region" => "region",
    "output_location" => "s3://my-bucket",
    "workgroup" => "primary"
  }

  @empty_required_fields %{
    "variable" => "db",
    "type" => "postgres",
    "hostname" => "",
    "port" => nil,
    "database_path" => "",
    "project_id" => "",
    "access_key_id" => "",
    "secret_access_key" => "",
    "region" => ""
  }

  describe "initialization" do
    test "returns default source when started with missing attrs" do
      {_kino, source} = start_smart_cell!(ConnectionCell, %{"variable" => "conn"})

      assert source ==
               """
               opts = [
                 hostname: "localhost",
                 port: 5432,
                 username: "",
                 password: "",
                 database: "",
                 socket_options: [:inet6]
               ]

               {:ok, conn} = Kino.start_child({Postgrex, opts})\
               """
    end
  end

  describe "code generation" do
    test "restores source code from attrs" do
      assert ConnectionCell.to_source(@attrs) === ~s'''
             opts = [
               hostname: "localhost",
               port: 4444,
               username: "admin",
               password: "pass",
               database: "default",
               socket_options: [:inet6]
             ]

             {:ok, db} = Kino.start_child({Postgrex, opts})\
             '''

      assert ConnectionCell.to_source(put_in(@attrs["type"], "mysql")) == ~s'''
             opts = [
               hostname: "localhost",
               port: 4444,
               username: "admin",
               password: "pass",
               database: "default",
               socket_options: [:inet6]
             ]

             {:ok, db} = Kino.start_child({MyXQL, opts})\
             '''

      assert ConnectionCell.to_source(put_in(@attrs["type"], "sqlite")) == ~s'''
             opts = [database: "/path/to/sqlite3.db"]
             {:ok, db} = Kino.start_child({Exqlite, opts})\
             '''

      assert ConnectionCell.to_source(put_in(@attrs["type"], "bigquery")) == ~s'''
             opts = [name: ReqBigQuery.Goth, http_client: &Req.request/1]
             {:ok, _pid} = Kino.start_child({Goth, opts})

             db =
               Req.new(http_errors: :raise)
               |> ReqBigQuery.attach(goth: ReqBigQuery.Goth, project_id: "foo", default_dataset_id: "")

             :ok\
             '''

      assert ConnectionCell.to_source(put_in(@attrs["type"], "athena")) == ~s'''
             db =
               Req.new(http_errors: :raise)
               |> ReqAthena.attach(
                 access_key_id: "id",
                 database: "default",
                 output_location: "s3://my-bucket",
                 region: "region",
                 secret_access_key: "secret",
                 token: "token",
                 workgroup: "primary"
               )

             :ok\
             '''
    end

    test "generates empty source code when required fields are missing" do
      assert ConnectionCell.to_source(put_in(@empty_required_fields["type"], "postgres")) == ""
      assert ConnectionCell.to_source(put_in(@empty_required_fields["type"], "mysql")) == ""
      assert ConnectionCell.to_source(put_in(@empty_required_fields["type"], "sqlite")) == ""
      assert ConnectionCell.to_source(put_in(@empty_required_fields["type"], "bigquery")) == ""
      assert ConnectionCell.to_source(put_in(@empty_required_fields["type"], "athena")) == ""
    end

    test "generates empty source code when all conditional fields are missing" do
      attrs = Map.merge(@attrs, %{"type" => "athena", "workgroup" => "", "output_location" => ""})

      assert ConnectionCell.to_source(attrs) == ""
    end
  end

  test "when a field changes, broadcasts the change and sends source update" do
    {kino, _source} = start_smart_cell!(ConnectionCell, %{"variable" => "conn"})

    push_event(kino, "update_field", %{"field" => "hostname", "value" => "myhost"})

    assert_broadcast_event(kino, "update", %{"fields" => %{"hostname" => "myhost"}})

    assert_smart_cell_update(kino, %{"hostname" => "myhost"}, """
    opts = [
      hostname: "myhost",
      port: 5432,
      username: "",
      password: "",
      database: "",
      socket_options: [:inet6]
    ]

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
    opts = [
      hostname: "localhost",
      port: 3306,
      username: "",
      password: "",
      database: "",
      socket_options: [:inet6]
    ]

    {:ok, conn} = Kino.start_child({MyXQL, opts})\
    """)
  end

  test "password from secrets" do
    {kino, _source} =
      start_smart_cell!(ConnectionCell, %{
        "variable" => "conn",
        "type" => "postgres",
        "port" => 5432
      })

    push_event(kino, "update_field", %{"field" => "use_password_secret", "value" => true})
    assert_broadcast_event(kino, "update", %{"fields" => %{"use_password_secret" => true}})

    push_event(kino, "update_field", %{"field" => "password_secret", "value" => "PASS"})
    assert_broadcast_event(kino, "update", %{"fields" => %{"password_secret" => "PASS"}})

    assert_smart_cell_update(
      kino,
      %{"password_secret" => "PASS"},
      """
      opts = [
        hostname: "localhost",
        port: 5432,
        username: "",
        password: System.fetch_env!("LB_PASS"),
        database: "",
        socket_options: [:inet6]
      ]

      {:ok, conn} = Kino.start_child({Postgrex, opts})\
      """
    )
  end
end
