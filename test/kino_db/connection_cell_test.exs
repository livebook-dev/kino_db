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
    "use_ipv6" => false,
    "use_ssl" => false,
    "cacertfile" => "",
    "auth_type" => "auth_jwt",
    "username" => "admin",
    "password" => "pass",
    "use_password_secret" => false,
    "password_secret" => "",
    "database" => "default",
    "database_path" => "/path/to/sqlite3.db",
    "project_id" => "foo",
    "credentials_json" => "",
    "default_dataset_id" => "",
    "access_key_id" => "id",
    "secret_access_key" => "secret",
    "use_secret_access_key_secret" => false,
    "secret_access_key_secret" => "",
    "private_key" => "-----BEGIN PRIVATE KEY-----...",
    "use_private_key_secret" => false,
    "private_key_secret" => "",
    "use_encrypted_private_key" => false,
    "private_key_passphrase" => "secret",
    "use_private_key_passphrase_secret" => false,
    "private_key_passphrase_secret" => "",
    "token" => "token",
    "region" => "region",
    "output_location" => "s3://my-bucket",
    "workgroup" => "primary",
    "account" => "account",
    "schema" => "schema",
    "warehouse" => ""
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
    "region" => "",
    "account" => "",
    "username" => "",
    "auth_type" => ""
  }

  describe "initialization" do
    test "returns default source when started with missing attrs" do
      {_kino, source} = start_smart_cell!(ConnectionCell, %{"variable" => "conn"})

      assert source ==
               """
               opts = [hostname: "localhost", port: 5432, username: "", password: "", database: ""]
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
               database: "default"
             ]

             {:ok, db} = Kino.start_child({Postgrex, opts})\
             '''

      attrs = Map.put(@attrs, "use_ipv6", true)

      assert ConnectionCell.to_source(attrs) === ~s'''
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

      attrs = Map.put(@attrs, "use_ssl", true)

      assert ConnectionCell.to_source(attrs) === ~s'''
             opts = [
               hostname: "localhost",
               port: 4444,
               username: "admin",
               password: "pass",
               database: "default",
               ssl: [cacerts: :public_key.cacerts_get()]
             ]

             {:ok, db} = Kino.start_child({Postgrex, opts})\
             '''

      attrs = Map.merge(@attrs, %{"use_ssl" => true, "cacertfile" => "/path/to/cacertfile"})

      assert ConnectionCell.to_source(attrs) === ~s'''
             opts = [
               hostname: "localhost",
               port: 4444,
               username: "admin",
               password: "pass",
               database: "default",
               ssl: [cacertfile: "/path/to/cacertfile"]
             ]

             {:ok, db} = Kino.start_child({Postgrex, opts})\
             '''

      attrs = Map.delete(@attrs, "password") |> Map.merge(%{"password_secret" => "PASS"})

      assert ConnectionCell.to_source(attrs) === ~s'''
             opts = [
               hostname: "localhost",
               port: 4444,
               username: "admin",
               password: System.fetch_env!("LB_PASS"),
               database: "default"
             ]

             {:ok, db} = Kino.start_child({Postgrex, opts})\
             '''

      assert ConnectionCell.to_source(put_in(@attrs["type"], "mysql")) == ~s'''
             opts = [
               hostname: "localhost",
               port: 4444,
               username: "admin",
               password: "pass",
               database: "default"
             ]

             {:ok, db} = Kino.start_child({MyXQL, opts})\
             '''

      assert ConnectionCell.to_source(put_in(@attrs["type"], "sqlite")) == ~s'''
             opts = [database: "/path/to/sqlite3.db"]
             {:ok, db} = Kino.start_child({Exqlite, opts})\
             '''

      assert ConnectionCell.to_source(put_in(@attrs["type"], "athena")) == ~s'''
             db =
               ReqAthena.new(
                 access_key_id: "id",
                 database: "default",
                 output_location: "s3://my-bucket",
                 region: "region",
                 secret_access_key: "secret",
                 token: "token",
                 workgroup: "primary",
                 http_errors: :raise
               )

             :ok\
             '''

      attrs =
        Map.delete(@attrs, "secret_access_key")
        |> Map.merge(%{"type" => "athena", "secret_access_key_secret" => "ATHENA_KEY"})

      assert ConnectionCell.to_source(attrs) == ~s'''
             db =
               ReqAthena.new(
                 access_key_id: "id",
                 database: "default",
                 output_location: "s3://my-bucket",
                 region: "region",
                 secret_access_key: System.fetch_env!("LB_ATHENA_KEY"),
                 token: "token",
                 workgroup: "primary",
                 http_errors: :raise
               )

             :ok\
             '''

      attrs =
        Map.delete(@attrs, "password_secret")
        |> Map.merge(%{"variable" => "conn", "auth_type" => "auth_snowflake"})

      assert ConnectionCell.to_source(put_in(attrs["type"], "snowflake")) == ~s'''
             :ok = Adbc.download_driver!(:snowflake)

             {:ok, db} =
               Kino.start_child(
                 {Adbc.Database,
                  driver: :snowflake,
                  username: "admin",
                  "adbc.snowflake.sql.account": "account",
                  "adbc.snowflake.sql.db": "default",
                  "adbc.snowflake.sql.schema": "schema",
                  "adbc.snowflake.sql.warehouse": "",
                  "adbc.snowflake.sql.auth_type": "auth_snowflake",
                  password: "pass"}
               )

             {:ok, conn} = Kino.start_child({Adbc.Connection, database: db})\
             '''

      assert ConnectionCell.to_source(put_in(attrs["type"], "clickhouse")) == ~s'''
             conn =
               ReqCH.new(
                 database: "default",
                 auth: {:basic, "admin:pass"},
                 base_url: "http://localhost:4444"
               )

             :ok\
             '''

      assert ConnectionCell.to_source(put_in(attrs["type"], "bigquery")) == ~s'''
             :ok = Adbc.download_driver!(:bigquery)

             {:ok, db} =
               Kino.start_child(
                 {Adbc.Database, driver: :bigquery, "adbc.bigquery.sql.project_id": "foo"}
               )

             {:ok, conn} = Kino.start_child({Adbc.Connection, database: db})\
             '''
    end

    test "generates empty source code when required fields are missing" do
      assert ConnectionCell.to_source(put_in(@empty_required_fields["type"], "postgres")) == ""
      assert ConnectionCell.to_source(put_in(@empty_required_fields["type"], "mysql")) == ""
      assert ConnectionCell.to_source(put_in(@empty_required_fields["type"], "sqlite")) == ""
      assert ConnectionCell.to_source(put_in(@empty_required_fields["type"], "bigquery")) == ""
      assert ConnectionCell.to_source(put_in(@empty_required_fields["type"], "athena")) == ""
      assert ConnectionCell.to_source(put_in(@empty_required_fields["type"], "snowflake")) == ""
      assert ConnectionCell.to_source(put_in(@empty_required_fields["type"], "clickhouse")) == ""
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
        database: ""
      ]

      {:ok, conn} = Kino.start_child({Postgrex, opts})\
      """
    )
  end

  test "athena secret key from secrets" do
    {kino, _source} =
      start_smart_cell!(ConnectionCell, %{
        "variable" => "conn",
        "type" => "athena",
        "database" => "default",
        "access_key_id" => "id",
        "secret_access_key" => "secret_key",
        "token" => "token",
        "region" => "region",
        "output_location" => "s3://my-bucket",
        "workgroup" => "primary"
      })

    push_event(kino, "update_field", %{"field" => "use_secret_access_key_secret", "value" => true})

    assert_broadcast_event(kino, "update", %{
      "fields" => %{"use_secret_access_key_secret" => true}
    })

    push_event(kino, "update_field", %{
      "field" => "secret_access_key_secret",
      "value" => "ATHENA_KEY"
    })

    assert_broadcast_event(kino, "update", %{
      "fields" => %{"secret_access_key_secret" => "ATHENA_KEY"}
    })

    assert_smart_cell_update(
      kino,
      %{"secret_access_key_secret" => "ATHENA_KEY"},
      """
      conn =
        ReqAthena.new(
          access_key_id: "id",
          database: "default",
          output_location: "s3://my-bucket",
          region: "region",
          secret_access_key: System.fetch_env!("LB_ATHENA_KEY"),
          token: "token",
          workgroup: "primary",
          http_errors: :raise
        )

      :ok\
      """
    )
  end
end
