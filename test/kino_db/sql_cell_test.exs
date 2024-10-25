defmodule KinoDB.SQLCellTest do
  use ExUnit.Case, async: true

  import Kino.Test

  alias KinoDB.SQLCell

  setup :configure_livebook_bridge

  describe "initialization" do
    test "restores source code from attrs" do
      attrs = %{
        "connection" => %{"variable" => "db", "type" => "postgres"},
        "result_variable" => "ids_result",
        "timeout" => nil,
        "query" => "SELECT id FROM users",
        "data_frame_alias" => Explorer.DataFrame
      }

      {_kino, source} = start_smart_cell!(SQLCell, attrs)

      assert source ==
               """
               ids_result = Postgrex.query!(db, ~S"SELECT id FROM users", [])\
               """
    end
  end

  test "when an invalid result variable name is set, restores the previous value" do
    {kino, _source} = start_smart_cell!(SQLCell, %{"result_variable" => "result"})

    push_event(kino, "update_result_variable", "RESULT")

    assert_broadcast_event(kino, "update_result_variable", "result")
  end

  test "finds database connections in binding and sends them to the client" do
    {kino, _source} = start_smart_cell!(SQLCell, %{})

    conn_pid = spawn_fake_postgrex_connection()

    binding = [non_conn: self(), conn: conn_pid]
    env = Code.env_for_eval([])
    SQLCell.scan_binding(kino.pid, binding, env)

    connection = %{variable: "conn", type: "postgres"}

    assert_broadcast_event(kino, "connections", %{
      "connections" => [^connection],
      "connection" => ^connection
    })
  end

  test "keeps the currently selected connection if not available in binding" do
    attrs = %{"connection" => %{"variable" => "conn1", "type" => "postgres"}}
    {kino, _source} = start_smart_cell!(SQLCell, attrs)

    conn_pid = spawn_fake_postgrex_connection()

    binding = [conn: conn_pid]
    env = Code.env_for_eval([])
    SQLCell.scan_binding(kino.pid, binding, env)

    current_connection = %{variable: "conn1", type: "postgres"}
    connection = %{variable: "conn", type: "postgres"}

    assert_broadcast_event(kino, "connections", %{
      "connections" => [^connection],
      "connection" => ^current_connection
    })
  end

  test "updates the selected connection type when the variable changes" do
    attrs = %{"connection" => %{"variable" => "conn", "type" => "sqlite"}}
    {kino, _source} = start_smart_cell!(SQLCell, attrs)

    conn_pid = spawn_fake_postgrex_connection()

    binding = [conn: conn_pid]
    env = Code.env_for_eval([])
    SQLCell.scan_binding(kino.pid, binding, env)

    connection = %{variable: "conn", type: "postgres"}

    assert_broadcast_event(kino, "connections", %{
      "connections" => [^connection],
      "connection" => ^connection
    })
  end

  describe "code generation" do
    test "uses regular string for a single-line query" do
      attrs = %{
        "connection" => %{"variable" => "conn", "type" => "postgres"},
        "result_variable" => "result",
        "timeout" => nil,
        "query" => "SELECT id FROM users",
        "data_frame_alias" => Explorer.DataFrame
      }

      assert SQLCell.to_source(attrs) == """
             result = Postgrex.query!(conn, ~S"SELECT id FROM users", [])\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "mysql")) == """
             result = MyXQL.query!(conn, ~S"SELECT id FROM users", [])\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "sqlite")) == """
             result = Exqlite.query!(conn, ~S"SELECT id FROM users", [])\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "bigquery")) == """
             result = Req.post!(conn, bigquery: {~S"SELECT id FROM users", []}).body\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "athena")) == """
             result = Req.post!(conn, athena: {~S"SELECT id FROM users", []}).body\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "snowflake")) == """
             result = Explorer.DataFrame.from_query!(conn, ~S"SELECT id FROM users", [])\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "clickhouse")) == """
             result = Ch.query!(conn, ~S"SELECT id FROM users", [])\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "sqlserver")) == """
             result = Tds.query!(conn, ~S"SELECT id FROM users", [])\
             """
    end

    test "uses heredoc string for a multi-line query" do
      attrs = %{
        "connection" => %{"variable" => "conn", "type" => "postgres"},
        "result_variable" => "result",
        "timeout" => nil,
        "query" => "SELECT id FROM users\nWHERE last_name = 'Sherlock'",
        "data_frame_alias" => Explorer.DataFrame
      }

      assert SQLCell.to_source(attrs) == ~s'''
             result =
               Postgrex.query!(
                 conn,
                 ~S"""
                 SELECT id FROM users
                 WHERE last_name = 'Sherlock'
                 """,
                 []
               )\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "mysql")) == ~s'''
             result =
               MyXQL.query!(
                 conn,
                 ~S"""
                 SELECT id FROM users
                 WHERE last_name = 'Sherlock'
                 """,
                 []
               )\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "sqlite")) == ~s'''
             result =
               Exqlite.query!(
                 conn,
                 ~S"""
                 SELECT id FROM users
                 WHERE last_name = 'Sherlock'
                 """,
                 []
               )\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "bigquery")) == ~s'''
             result =
               Req.post!(conn,
                 bigquery:
                   {~S"""
                    SELECT id FROM users
                    WHERE last_name = 'Sherlock'
                    """, []}
               ).body\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "athena")) == ~s'''
             result =
               Req.post!(conn,
                 athena:
                   {~S"""
                    SELECT id FROM users
                    WHERE last_name = 'Sherlock'
                    """, []}
               ).body\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "snowflake")) == ~s'''
             result =
               Explorer.DataFrame.from_query!(
                 conn,
                 ~S"""
                 SELECT id FROM users
                 WHERE last_name = 'Sherlock'
                 """,
                 []
               )\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "clickhouse")) == ~s'''
             result =
               Ch.query!(
                 conn,
                 ~S"""
                 SELECT id FROM users
                 WHERE last_name = 'Sherlock'
                 """,
                 []
               )\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "sqlserver")) == ~s'''
             result =
               Tds.query!(
                 conn,
                 ~S"""
                 SELECT id FROM users
                 WHERE last_name = 'Sherlock'
                 """,
                 []
               )\
             '''
    end

    test "parses parameter expressions" do
      attrs = %{
        "connection" => %{"variable" => "conn", "type" => "postgres"},
        "result_variable" => "result",
        "timeout" => nil,
        "query" => ~s/SELECT id FROM users WHERE id {{user_id}} AND name LIKE {{search <> "%"}}/,
        "data_frame_alias" => Explorer.DataFrame
      }

      assert SQLCell.to_source(attrs) == ~s'''
             result =
               Postgrex.query!(conn, ~S"SELECT id FROM users WHERE id $1 AND name LIKE $2", [
                 user_id,
                 search <> "%"
               ])\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "mysql")) == ~s'''
             result =
               MyXQL.query!(conn, ~S"SELECT id FROM users WHERE id ? AND name LIKE ?", [
                 user_id,
                 search <> "%"
               ])\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "sqlite")) == ~s'''
             result =
               Exqlite.query!(conn, ~S"SELECT id FROM users WHERE id ?1 AND name LIKE ?2", [
                 user_id,
                 search <> "%"
               ])\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "bigquery")) == ~s'''
             result =
               Req.post!(conn,
                 bigquery:
                   {~S"SELECT id FROM users WHERE id ? AND name LIKE ?", [user_id, search <> "%"]}
               ).body\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "athena")) == ~s'''
             result =
               Req.post!(conn,
                 athena:
                   {~S"SELECT id FROM users WHERE id ? AND name LIKE ?", [user_id, search <> "%"]}
               ).body\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "snowflake")) == ~s'''
             result =
               Explorer.DataFrame.from_query!(
                 conn,
                 ~S"SELECT id FROM users WHERE id ?1 AND name LIKE ?2",
                 [user_id, search <> \"%\"]
               )\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "clickhouse")) == ~s'''
             result =
               Ch.query!(
                 conn,
                 ~S"SELECT id FROM users WHERE id {$1:String} AND name LIKE {$2:String}",
                 [user_id, search <> \"%\"]
               )\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "sqlserver")) == ~s'''
             result =
               Tds.query!(conn, ~S"SELECT id FROM users WHERE id @1 AND name LIKE @2", [
                 %Tds.Parameter{name: "@1", value: user_id},
                 %Tds.Parameter{name: "@2", value: search <> "%"}
               ])\
             '''
    end

    test "ignores parameters inside comments" do
      attrs = %{
        "connection" => %{"variable" => "conn", "type" => "postgres"},
        "result_variable" => "result",
        "timeout" => nil,
        "query" => """
        SELECT id from users
        -- WHERE id = {{user_id1}}
        /* WHERE id = {{user_id2}} */ WHERE id = {{user_id3}}\
        """,
        "data_frame_alias" => Explorer.DataFrame
      }

      assert SQLCell.to_source(attrs) == ~s'''
             result =
               Postgrex.query!(
                 conn,
                 ~S"""
                 SELECT id from users
                 -- WHERE id = {{user_id1}}
                 /* WHERE id = {{user_id2}} */ WHERE id = $1
                 """,
                 [user_id3]
               )\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "mysql")) == ~s'''
             result =
               MyXQL.query!(
                 conn,
                 ~S"""
                 SELECT id from users
                 -- WHERE id = {{user_id1}}
                 /* WHERE id = {{user_id2}} */ WHERE id = ?
                 """,
                 [user_id3]
               )\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "sqlite")) == ~s'''
             result =
               Exqlite.query!(
                 conn,
                 ~S"""
                 SELECT id from users
                 -- WHERE id = {{user_id1}}
                 /* WHERE id = {{user_id2}} */ WHERE id = ?1
                 """,
                 [user_id3]
               )\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "bigquery")) == ~s'''
             result =
               Req.post!(conn,
                 bigquery:
                   {~S"""
                    SELECT id from users
                    -- WHERE id = {{user_id1}}
                    /* WHERE id = {{user_id2}} */ WHERE id = ?
                    """, [user_id3]}
               ).body\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "athena")) == ~s'''
             result =
               Req.post!(conn,
                 athena:
                   {~S"""
                    SELECT id from users
                    -- WHERE id = {{user_id1}}
                    /* WHERE id = {{user_id2}} */ WHERE id = ?
                    """, [user_id3]}
               ).body\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "snowflake")) == ~s'''
             result =
               Explorer.DataFrame.from_query!(
                 conn,
                 ~S"""
                 SELECT id from users
                 -- WHERE id = {{user_id1}}
                 /* WHERE id = {{user_id2}} */ WHERE id = ?1
                 """,
                 [user_id3]
               )\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "clickhouse")) == ~s'''
             result =
               Ch.query!(
                 conn,
                 ~S"""
                 SELECT id from users
                 -- WHERE id = {{user_id1}}
                 /* WHERE id = {{user_id2}} */ WHERE id = {$1:String}
                 """,
                 [user_id3]
               )\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "sqlserver")) == ~s'''
             result =
               Tds.query!(
                 conn,
                 ~S"""
                 SELECT id from users
                 -- WHERE id = {{user_id1}}
                 /* WHERE id = {{user_id2}} */ WHERE id = @1
                 """,
                 [%Tds.Parameter{name: "@1", value: user_id3}]
               )\
             '''
    end

    test "passes timeout option when a timeout is specified" do
      attrs = %{
        "connection" => %{"variable" => "conn", "type" => "postgres"},
        "result_variable" => "result",
        "timeout" => 30,
        "query" => "SELECT id FROM users",
        "data_frame_alias" => Explorer.DataFrame
      }

      assert SQLCell.to_source(attrs) == """
             result = Postgrex.query!(conn, ~S"SELECT id FROM users", [], timeout: 30000)\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "mysql")) == """
             result = MyXQL.query!(conn, ~S"SELECT id FROM users", [], timeout: 30000)\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "sqlite")) == """
             result = Exqlite.query!(conn, ~S"SELECT id FROM users", [], timeout: 30000)\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "bigquery")) == """
             result = Req.post!(conn, bigquery: {~S"SELECT id FROM users", []}).body\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "athena")) == """
             result = Req.post!(conn, athena: {~S"SELECT id FROM users", []}).body\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "snowflake")) == """
             result = Explorer.DataFrame.from_query!(conn, ~S"SELECT id FROM users", [])\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "clickhouse")) == """
             result = Ch.query!(conn, ~S"SELECT id FROM users", [])\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "sqlserver")) == """
             result = Tds.query!(conn, ~S"SELECT id FROM users", [], timeout: 30000)\
             """
    end

    test "passes cache_query option when supported" do
      attrs = %{
        "connection" => %{"variable" => "conn", "type" => "postgres"},
        "result_variable" => "result",
        "cache_query" => true,
        "query" => "SELECT id FROM users",
        "data_frame_alias" => DF
      }

      assert SQLCell.to_source(attrs) == """
             result = Postgrex.query!(conn, ~S"SELECT id FROM users", [])\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "mysql")) == """
             result = MyXQL.query!(conn, ~S"SELECT id FROM users", [])\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "sqlite")) == """
             result = Exqlite.query!(conn, ~S"SELECT id FROM users", [])\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "snowflake")) == """
             result = DF.from_query!(conn, ~S"SELECT id FROM users", [])\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "clickhouse")) == """
             result = Ch.query!(conn, ~S"SELECT id FROM users", [])\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "bigquery")) == """
             result = Req.post!(conn, bigquery: {~S"SELECT id FROM users", []}).body\
             """

      athena = put_in(attrs["connection"]["type"], "athena")

      assert SQLCell.to_source(put_in(athena["cache_query"], true)) == """
             result = Req.post!(conn, athena: {~S"SELECT id FROM users", []}, cache_query: true).body\
             """

      assert SQLCell.to_source(put_in(athena["cache_query"], false)) == """
             result = Req.post!(conn, athena: {~S"SELECT id FROM users", []}, cache_query: false).body\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "sqlserver")) == """
             result = Tds.query!(conn, ~S"SELECT id FROM users", [])\
             """
    end

    test "escapes interpolation" do
      attrs = %{
        "connection" => %{"variable" => "conn", "type" => "postgres"},
        "result_variable" => "result",
        "timeout" => nil,
        "query" => "SELECT id FROM users WHERE last_name = '\#{user_id}'",
        "data_frame_alias" => Explorer.DataFrame
      }

      assert SQLCell.to_source(attrs) == """
             result =
               Postgrex.query!(conn, ~S"SELECT id FROM users WHERE last_name = '\#{user_id}'", [])\
             """

      athena = put_in(attrs["query"], "SELECT id FROM users\nWHERE last_name = '\#{user_id}'")

      assert SQLCell.to_source(put_in(athena["cache_query"], true)) == ~s'''
             result =
               Postgrex.query!(
                 conn,
                 ~S"""
                 SELECT id FROM users
                 WHERE last_name = '\#{user_id}'
                 """,
                 []
               )\
             '''
    end
  end

  defp spawn_fake_postgrex_connection() do
    parent = self()

    conn =
      spawn_link(fn ->
        # Pretend we are a connection pool for Postgrex
        DBConnection.register_as_pool(Postgrex.Protocol)
        send(parent, {:ready, self()})
        receive do: (:stop -> :ok)
      end)

    on_exit(fn ->
      send(conn, :stop)
    end)

    receive do: ({:ready, ^conn} -> conn)
  end
end
