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
        "query" => "SELECT id FROM users"
      }

      {_kino, source} = start_smart_cell!(SQLCell, attrs)

      assert source ==
               """
               ids_result = Postgrex.query!(db, "SELECT id FROM users", [])\
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

    parent = self()

    spawn_link(fn ->
      # Pretend we are a connection pool for Postgrex
      DBConnection.register_as_pool(Postgrex.Protocol)
      send(parent, {:ready, self()})
      assert_receive :stop
    end)

    assert_receive {:ready, conn_pid}

    binding = [non_conn: self(), conn: conn_pid]
    # TODO: Use Code.env_for_eval on Elixir v1.14+
    env = :elixir.env_for_eval([])
    SQLCell.scan_binding(kino.pid, binding, env)

    connection = %{variable: "conn", type: "postgres"}

    assert_broadcast_event(kino, "connections", %{
      "connections" => [^connection],
      "connection" => ^connection
    })

    send(conn_pid, :stop)
  end

  describe "code generation" do
    test "uses regular string for a single-line query" do
      attrs = %{
        "connection" => %{"variable" => "conn", "type" => "postgres"},
        "result_variable" => "result",
        "timeout" => nil,
        "query" => "SELECT id FROM users"
      }

      assert SQLCell.to_source(attrs) == """
             result = Postgrex.query!(conn, "SELECT id FROM users", [])\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "mysql")) == """
             result = MyXQL.query!(conn, "SELECT id FROM users", [])\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "sqlite")) == """
             result = Exqlite.query!(conn, "SELECT id FROM users", [])\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "bigquery")) == """
             result = Req.post!(conn, bigquery: {\"SELECT id FROM users\", []}).body\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "athena")) == """
             result = Req.post!(conn, athena: {\"SELECT id FROM users\", []}).body\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "snowflake")) == """
             result = Adbc.Connection.query!(conn, "SELECT id FROM users", [])\
             """
    end

    test "uses heredoc string for a multi-line query" do
      attrs = %{
        "connection" => %{"variable" => "conn", "type" => "postgres"},
        "result_variable" => "result",
        "timeout" => nil,
        "query" => "SELECT id FROM users\nWHERE last_name = 'Sherlock'"
      }

      assert SQLCell.to_source(attrs) == ~s'''
             result =
               Postgrex.query!(
                 conn,
                 """
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
                 """
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
                 """
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
                   {"""
                    SELECT id FROM users
                    WHERE last_name = 'Sherlock'
                    """, []}
               ).body\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "athena")) == ~s'''
             result =
               Req.post!(conn,
                 athena:
                   {"""
                    SELECT id FROM users
                    WHERE last_name = 'Sherlock'
                    """, []}
               ).body\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "snowflake")) == ~s'''
             result =
               Adbc.Connection.query!(
                 conn,
                 """
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
        "query" => ~s/SELECT id FROM users WHERE id {{user_id}} AND name LIKE {{search <> "%"}}/
      }

      assert SQLCell.to_source(attrs) == ~s'''
             result =
               Postgrex.query!(conn, "SELECT id FROM users WHERE id $1 AND name LIKE $2", [
                 user_id,
                 search <> "%"
               ])\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "mysql")) == ~s'''
             result =
               MyXQL.query!(conn, "SELECT id FROM users WHERE id ? AND name LIKE ?", [
                 user_id,
                 search <> "%"
               ])\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "sqlite")) == ~s'''
             result =
               Exqlite.query!(conn, "SELECT id FROM users WHERE id ?1 AND name LIKE ?2", [
                 user_id,
                 search <> "%"
               ])\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "bigquery")) == ~s'''
             result =
               Req.post!(conn,
                 bigquery:
                   {"SELECT id FROM users WHERE id ? AND name LIKE ?", [user_id, search <> "%"]}
               ).body\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "athena")) == ~s'''
             result =
               Req.post!(conn,
                 athena: {"SELECT id FROM users WHERE id ? AND name LIKE ?", [user_id, search <> "%"]}
               ).body\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "snowflake")) == ~s'''
             result =
               Adbc.Connection.query!(conn, "SELECT id FROM users WHERE id ?1 AND name LIKE ?2", [
                 user_id,
                 search <> "%"
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
        """
      }

      assert SQLCell.to_source(attrs) == ~s'''
             result =
               Postgrex.query!(
                 conn,
                 """
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
                 """
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
                 """
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
                   {"""
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
                   {"""
                    SELECT id from users
                    -- WHERE id = {{user_id1}}
                    /* WHERE id = {{user_id2}} */ WHERE id = ?
                    """, [user_id3]}
               ).body\
             '''

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "snowflake")) == ~s'''
             result =
               Adbc.Connection.query!(
                 conn,
                 """
                 SELECT id from users
                 -- WHERE id = {{user_id1}}
                 /* WHERE id = {{user_id2}} */ WHERE id = ?1
                 """,
                 [user_id3]
               )\
             '''
    end

    test "passes timeout option when a timeout is specified" do
      attrs = %{
        "connection" => %{"variable" => "conn", "type" => "postgres"},
        "result_variable" => "result",
        "timeout" => 30,
        "query" => "SELECT id FROM users"
      }

      assert SQLCell.to_source(attrs) == """
             result = Postgrex.query!(conn, "SELECT id FROM users", [], timeout: 30000)\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "mysql")) == """
             result = MyXQL.query!(conn, "SELECT id FROM users", [], timeout: 30000)\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "sqlite")) == """
             result = Exqlite.query!(conn, "SELECT id FROM users", [], timeout: 30000)\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "bigquery")) == """
             result = Req.post!(conn, bigquery: {"SELECT id FROM users", []}).body\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "athena")) == """
             result = Req.post!(conn, athena: {"SELECT id FROM users", []}).body\
             """
    end

    test "passes cache_query option when supported" do
      attrs = %{
        "connection" => %{"variable" => "conn", "type" => "postgres"},
        "result_variable" => "result",
        "cache_query" => true,
        "query" => "SELECT id FROM users"
      }

      assert SQLCell.to_source(attrs) == """
             result = Postgrex.query!(conn, "SELECT id FROM users", [])\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "mysql")) == """
             result = MyXQL.query!(conn, "SELECT id FROM users", [])\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "sqlite")) == """
             result = Exqlite.query!(conn, "SELECT id FROM users", [])\
             """

      assert SQLCell.to_source(put_in(attrs["connection"]["type"], "bigquery")) == """
             result = Req.post!(conn, bigquery: {"SELECT id FROM users", []}).body\
             """

      athena = put_in(attrs["connection"]["type"], "athena")

      assert SQLCell.to_source(put_in(athena["cache_query"], true)) == """
             result = Req.post!(conn, athena: {"SELECT id FROM users", []}, cache_query: true).body\
             """

      assert SQLCell.to_source(put_in(athena["cache_query"], false)) == """
             result = Req.post!(conn, athena: {"SELECT id FROM users", []}, cache_query: false).body\
             """
    end
  end
end
