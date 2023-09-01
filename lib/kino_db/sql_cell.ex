defmodule KinoDB.SQLCell do
  @moduledoc false

  use Kino.JS, assets_path: "lib/assets/sql_cell"
  use Kino.JS.Live
  use Kino.SmartCell, name: "SQL query"

  @default_query "select * from table_name limit 100"

  @impl true
  def init(attrs, ctx) do
    connection =
      if conn_attrs = attrs["connection"] do
        %{variable: conn_attrs["variable"], type: conn_attrs["type"]}
      end

    ctx =
      assign(ctx,
        connections: [],
        connection: connection,
        result_variable: Kino.SmartCell.prefixed_var_name("result", attrs["result_variable"]),
        timeout: attrs["timeout"],
        cache_query: attrs["cache_query"] || true,
        data_frame_alias: Explorer.DataFrame,
        missing_dep: missing_dep(connection)
      )

    {:ok, ctx, editor: [attribute: "query", language: "sql", default_source: @default_query]}
  end

  @impl true
  def handle_connect(ctx) do
    payload = %{
      connections: ctx.assigns.connections,
      connection: ctx.assigns.connection,
      result_variable: ctx.assigns.result_variable,
      timeout: ctx.assigns.timeout,
      cache_query: ctx.assigns.cache_query,
      data_frame_alias: ctx.assigns.data_frame_alias,
      missing_dep: ctx.assigns.missing_dep
    }

    {:ok, payload, ctx}
  end

  @impl true
  def handle_event("update_connection", variable, ctx) do
    connection = Enum.find(ctx.assigns.connections, &(&1.variable == variable))
    ctx = assign(ctx, connection: connection)
    missing_dep = missing_dep(connection)

    ctx =
      if missing_dep == ctx.assigns.missing_dep do
        ctx
      else
        broadcast_event(ctx, "missing_dep", %{"dep" => missing_dep})
        assign(ctx, missing_dep: missing_dep)
      end

    broadcast_event(ctx, "update_connection", connection.variable)

    {:noreply, ctx}
  end

  def handle_event("update_result_variable", variable, ctx) do
    ctx =
      if Kino.SmartCell.valid_variable_name?(variable) do
        broadcast_event(ctx, "update_result_variable", variable)
        assign(ctx, result_variable: variable)
      else
        broadcast_event(ctx, "update_result_variable", ctx.assigns.result_variable)
        ctx
      end

    {:noreply, ctx}
  end

  def handle_event("update_timeout", timeout, ctx) do
    timeout =
      case Integer.parse(timeout) do
        {n, ""} -> n
        _ -> nil
      end

    ctx = assign(ctx, timeout: timeout)
    broadcast_event(ctx, "update_timeout", timeout)
    {:noreply, ctx}
  end

  def handle_event("update_cache_query", cache_query?, ctx) do
    ctx = assign(ctx, cache_query: cache_query?)
    broadcast_event(ctx, "update_cache_query", cache_query?)
    {:noreply, ctx}
  end

  @impl true
  def scan_binding(pid, binding, env) do
    connections =
      for {key, value} <- binding,
          is_atom(key),
          type = connection_type(value),
          do: %{variable: Atom.to_string(key), type: type}

    data_frame_alias = data_frame_alias(env)

    send(pid, {:connections, connections, data_frame_alias})
  end

  @impl true
  def handle_info({:connections, connections, data_frame_alias}, ctx) do
    connection = search_connection(connections, ctx.assigns.connection)
    missing_dep = missing_dep(connection)

    ctx =
      if missing_dep == ctx.assigns.missing_dep do
        ctx
      else
        broadcast_event(ctx, "missing_dep", %{"dep" => missing_dep})
        assign(ctx, missing_dep: missing_dep)
      end

    broadcast_event(ctx, "connections", %{
      "connections" => connections,
      "connection" => connection
    })

    {:noreply,
     assign(ctx,
       connections: connections,
       connection: connection,
       data_frame_alias: data_frame_alias
     )}
  end

  defp search_connection([connection | _], nil), do: connection

  defp search_connection([], connection), do: connection

  defp search_connection(connections, %{variable: variable}) do
    case Enum.find(connections, &(&1.variable == variable)) do
      nil -> List.first(connections)
      connection -> connection
    end
  end

  @compile {:no_warn_undefined, {DBConnection, :connection_module, 1}}

  defp connection_type(connection) when is_pid(connection) do
    with true <- Code.ensure_loaded?(DBConnection),
         {:ok, module} <- DBConnection.connection_module(connection) do
      case Atom.to_string(module) do
        "Elixir.Postgrex" <> _ -> "postgres"
        "Elixir.MyXQL" <> _ -> "mysql"
        "Elixir.Exqlite" <> _ -> "sqlite"
        "Elixir.Tds" <> _ -> "sqlserver"
        _ -> nil
      end
    else
      _ -> connection_type_from_adbc(connection)
    end
  end

  defp connection_type(connection) when is_struct(connection, Req.Request) do
    cond do
      Keyword.has_key?(connection.request_steps, :bigquery_run) -> "bigquery"
      Keyword.has_key?(connection.request_steps, :athena_run) -> "athena"
      true -> nil
    end
  end

  defp connection_type(_connection), do: nil

  defp connection_type_from_adbc(connection) when is_pid(connection) do
    with true <- Code.ensure_loaded?(Adbc),
         {:ok, driver} <- Adbc.Connection.get_driver(connection) do
      Atom.to_string(driver)
    else
      _ -> nil
    end
  end

  @impl true
  def to_attrs(ctx) do
    %{
      "connection" =>
        if connection = ctx.assigns.connection do
          %{"variable" => connection.variable, "type" => connection.type}
        end,
      "result_variable" => ctx.assigns.result_variable,
      "timeout" => ctx.assigns.timeout,
      "cache_query" => ctx.assigns.cache_query,
      "data_frame_alias" => ctx.assigns.data_frame_alias
    }
  end

  @impl true
  def to_source(attrs) do
    attrs |> to_quoted() |> Kino.SmartCell.quoted_to_string()
  end

  defp to_quoted(%{"connection" => %{"type" => "postgres"}} = attrs) do
    to_quoted(attrs, quote(do: Postgrex), fn n -> "$#{n}" end)
  end

  defp to_quoted(%{"connection" => %{"type" => "mysql"}} = attrs) do
    to_quoted(attrs, quote(do: MyXQL), fn _n -> "?" end)
  end

  defp to_quoted(%{"connection" => %{"type" => "sqlite"}} = attrs) do
    to_quoted(attrs, quote(do: Exqlite), fn n -> "?#{n}" end)
  end

  defp to_quoted(%{"connection" => %{"type" => "snowflake"}} = attrs) do
    to_explorer_quoted(attrs, fn n -> "?#{n}" end)
  end

  defp to_quoted(%{"connection" => %{"type" => "sqlserver"}} = attrs) do
    to_quoted(attrs, quote(do: Tds), fn n -> "@#{n}" end)
  end

  defp to_quoted(%{"connection" => %{"type" => "bigquery"}} = attrs) do
    to_req_quoted(attrs, fn _n -> "?" end, :bigquery)
  end

  defp to_quoted(%{"connection" => %{"type" => "athena"}} = attrs) do
    to_req_quoted(attrs, fn _n -> "?" end, :athena)
  end

  defp to_quoted(_ctx) do
    quote do
    end
  end

  defp to_quoted(attrs, quoted_module, next) do
    {query, params} = parameterize(attrs["query"], attrs["connection"]["type"], next)
    opts_args = query_opts_args(attrs)

    quote do
      unquote(quoted_var(attrs["result_variable"])) =
        unquote(quoted_module).query!(
          unquote(quoted_var(attrs["connection"]["variable"])),
          unquote(quoted_query(query)),
          unquote(params),
          unquote_splicing(opts_args)
        )
    end
  end

  defp to_req_quoted(attrs, next, req_key) do
    {query, params} = parameterize(attrs["query"], attrs["connection"]["type"], next)
    query = {quoted_query(query), params}
    opts = query_opts_args(attrs)
    req_opts = opts |> Enum.at(0, []) |> Keyword.put(req_key, query)

    quote do
      unquote(quoted_var(attrs["result_variable"])) =
        Req.post!(
          unquote(quoted_var(attrs["connection"]["variable"])),
          unquote(req_opts)
        ).body
    end
  end

  defp to_explorer_quoted(attrs, next) do
    {query, params} = parameterize(attrs["query"], attrs["connection"]["type"], next)
    data_frame_alias = attrs["data_frame_alias"]

    quote do
      unquote(quoted_var(attrs["result_variable"])) =
        unquote(data_frame_alias).from_query!(
          unquote(quoted_var(attrs["connection"]["variable"])),
          unquote(quoted_query(query)),
          unquote(params)
        )
    end
  end

  defp quoted_var(nil), do: nil
  defp quoted_var(string), do: {String.to_atom(string), [], nil}

  defp quoted_query(query) do
    if String.contains?(query, "\n") do
      {:<<>>, [delimiter: ~s["""]], [query <> "\n"]}
    else
      query
    end
  end

  @connection_types_with_timeout ~w|postgres mysql sqlite sqlserver|

  defp query_opts_args(%{"connection" => %{"type" => type}, "timeout" => timeout})
       when timeout != nil and type in @connection_types_with_timeout,
       do: [[timeout: timeout * 1000]]

  defp query_opts_args(%{"connection" => %{"type" => "athena"}, "cache_query" => cache_query}),
    do: [[cache_query: cache_query]]

  defp query_opts_args(_attrs), do: []

  defp parameterize(query, type, next) do
    parameterize(query, "", [], 1, type, next)
  end

  defp parameterize("", raw, params, _n, _type, _next) do
    {raw, Enum.reverse(params)}
  end

  defp parameterize("--" <> _ = query, raw, params, n, type, next) do
    {comment, rest} =
      case String.split(query, "\n", parts: 2) do
        [comment, rest] -> {comment <> "\n", rest}
        [comment] -> {comment, ""}
      end

    parameterize(rest, raw <> comment, params, n, type, next)
  end

  defp parameterize("/*" <> _ = query, raw, params, n, type, next) do
    {comment, rest} =
      case String.split(query, "*/", parts: 2) do
        [comment, rest] -> {comment <> "*/", rest}
        [comment] -> {comment, ""}
      end

    parameterize(rest, raw <> comment, params, n, type, next)
  end

  defp parameterize("{{" <> rest = query, raw, params, n, type, next) do
    with [inner, rest] <- String.split(rest, "}}", parts: 2),
         sql_param <- next.(n),
         {:ok, param} <- quote_param(type, inner, sql_param) do
      parameterize(rest, raw <> sql_param, [param | params], n + 1, type, next)
    else
      _ -> parameterize("", raw <> query, params, n, type, next)
    end
  end

  defp parameterize(<<char::utf8, rest::binary>>, raw, params, n, type, next) do
    parameterize(rest, <<raw::binary, char::utf8>>, params, n, type, next)
  end

  defp quote_param("sqlserver", inner, sql_param) do
    Code.string_to_quoted("%Tds.Parameter{name: \"#{sql_param}\", value: #{inner}}")
  end

  defp quote_param(_type, inner, _sql_param) do
    Code.string_to_quoted(inner)
  end

  defp data_frame_alias(%Macro.Env{aliases: aliases}) do
    case List.keyfind(aliases, Explorer.DataFrame, 1) do
      {data_frame_alias, _} -> data_frame_alias
      nil -> Explorer.DataFrame
    end
  end

  defp missing_dep(%{type: "snowflake"}) do
    unless Code.ensure_loaded?(Explorer) do
      ~s|{:explorer, "~> 0.7.0"}|
    end
  end

  defp missing_dep(_), do: nil
end
