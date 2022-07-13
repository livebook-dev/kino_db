defmodule KinoDB.SQLCell do
  @moduledoc false

  use Kino.JS, assets_path: "lib/assets/sql_cell"
  use Kino.JS.Live
  use Kino.SmartCell, name: "SQL query"

  @default_query "select * from table_name limit 100"

  @impl true
  def init(attrs, ctx) do
    ctx =
      assign(ctx,
        connections: [],
        connection:
          if conn_attrs = attrs["connection"] do
            %{variable: conn_attrs["variable"], type: conn_attrs["type"]}
          end,
        result_variable: Kino.SmartCell.prefixed_var_name("result", attrs["result_variable"]),
        timeout: attrs["timeout"],
        cache_query: attrs["cache_query"] || true
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
      cache_query: ctx.assigns.cache_query
    }

    {:ok, payload, ctx}
  end

  @impl true
  def handle_event("update_connection", variable, ctx) do
    connection = Enum.find(ctx.assigns.connections, &(&1.variable == variable))
    ctx = assign(ctx, connection: connection)
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
  def scan_binding(pid, binding, _env) do
    connections =
      for {key, value} <- binding,
          is_atom(key),
          type = connection_type(value),
          do: %{variable: Atom.to_string(key), type: type}

    send(pid, {:connections, connections})
  end

  @impl true
  def handle_info({:connections, connections}, ctx) do
    connection = search_connection(connections, ctx.assigns.connection)

    broadcast_event(ctx, "connections", %{
      "connections" => connections,
      "connection" => connection
    })

    {:noreply, assign(ctx, connections: connections, connection: connection)}
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
        _ -> nil
      end
    else
      _ -> nil
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

  @impl true
  def to_attrs(ctx) do
    %{
      "connection" =>
        if connection = ctx.assigns.connection do
          %{"variable" => connection.variable, "type" => connection.type}
        end,
      "result_variable" => ctx.assigns.result_variable,
      "timeout" => ctx.assigns.timeout,
      "cache_query" => ctx.assigns.cache_query
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
    {query, params} = parameterize(attrs["query"], next)
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
    {query, params} = parameterize(attrs["query"], next)
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

  defp quoted_var(nil), do: nil
  defp quoted_var(string), do: {String.to_atom(string), [], nil}

  defp quoted_query(query) do
    if String.contains?(query, "\n") do
      {:<<>>, [delimiter: ~s["""]], [query <> "\n"]}
    else
      query
    end
  end

  @connection_types_with_timeout ~w|postgres mysql|

  defp query_opts_args(%{"connection" => %{"type" => type}, "timeout" => timeout})
       when timeout != nil and type in @connection_types_with_timeout,
       do: [[timeout: timeout * 1000]]

  defp query_opts_args(%{"connection" => %{"type" => "athena"}, "cache_query" => cache_query}),
    do: [[cache_query: cache_query]]

  defp query_opts_args(_attrs), do: []

  defp parameterize(query, next) do
    parameterize(query, "", [], 1, next)
  end

  defp parameterize("", raw, params, _n, _next) do
    {raw, Enum.reverse(params)}
  end

  defp parameterize("--" <> _ = query, raw, params, n, next) do
    {comment, rest} =
      case String.split(query, "\n", parts: 2) do
        [comment, rest] -> {comment <> "\n", rest}
        [comment] -> {comment, ""}
      end

    parameterize(rest, raw <> comment, params, n, next)
  end

  defp parameterize("/*" <> _ = query, raw, params, n, next) do
    {comment, rest} =
      case String.split(query, "*/", parts: 2) do
        [comment, rest] -> {comment <> "*/", rest}
        [comment] -> {comment, ""}
      end

    parameterize(rest, raw <> comment, params, n, next)
  end

  defp parameterize("{{" <> rest = query, raw, params, n, next) do
    with [inner, rest] <- String.split(rest, "}}", parts: 2),
         {:ok, param} <- Code.string_to_quoted(inner) do
      parameterize(rest, raw <> next.(n), [param | params], n + 1, next)
    else
      _ -> parameterize("", raw <> query, params, n, next)
    end
  end

  defp parameterize(<<char::utf8, rest::binary>>, raw, params, n, next) do
    parameterize(rest, <<raw::binary, char::utf8>>, params, n, next)
  end
end
