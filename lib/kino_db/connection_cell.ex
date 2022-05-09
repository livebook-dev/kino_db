defmodule KinoDB.ConnectionCell do
  @moduledoc false

  # A smart cell used to establish connection to a database.

  use Kino.JS, assets_path: "lib/assets/connection_cell"
  use Kino.JS.Live
  use Kino.SmartCell, name: "Database connection"

  @default_port_by_type %{"postgres" => 5432, "mysql" => 3306}

  @impl true
  def init(attrs, ctx) do
    type = attrs["type"] || default_db_type()
    default_port = @default_port_by_type[type]

    fields = %{
      "variable" => Kino.SmartCell.prefixed_var_name("conn", attrs["variable"]),
      "type" => type,
      "hostname" => attrs["hostname"] || "localhost",
      "database_path" => attrs["database_path"] || "",
      "port" => attrs["port"] || default_port,
      "username" => attrs["username"] || "",
      "password" => attrs["password"] || "",
      "database" => attrs["database"] || "",
      "project_id" => attrs["project_id"] || "",
      "default_dataset_id" => attrs["default_dataset_id"] || "",
      "private_key_id" => attrs["private_key_id"] || "",
      "private_key" => attrs["private_key"] || "",
      "client_email" => attrs["client_email"] || "",
      "client_id" => attrs["client_id"] || ""
    }

    {:ok, assign(ctx, fields: fields, missing_dep: missing_dep(fields))}
  end

  @impl true
  def handle_connect(ctx) do
    payload = %{
      fields: ctx.assigns.fields,
      missing_dep: ctx.assigns.missing_dep
    }

    {:ok, payload, ctx}
  end

  @impl true
  def handle_event("update_field", %{"field" => field, "value" => value}, ctx) do
    updated_fields = to_updates(ctx.assigns.fields, field, value)
    ctx = update(ctx, :fields, &Map.merge(&1, updated_fields))

    missing_dep = missing_dep(ctx.assigns.fields)

    ctx =
      if missing_dep == ctx.assigns.missing_dep do
        ctx
      else
        broadcast_event(ctx, "missing_dep", %{"dep" => missing_dep})
        assign(ctx, missing_dep: missing_dep)
      end

    broadcast_event(ctx, "update", %{"fields" => updated_fields})

    {:noreply, ctx}
  end

  defp to_updates(_fields, "port", value) do
    port =
      case Integer.parse(value) do
        {n, ""} -> n
        _ -> nil
      end

    %{"port" => port}
  end

  defp to_updates(_fields, "type", value) do
    %{"type" => value, "port" => @default_port_by_type[value]}
  end

  defp to_updates(fields, "variable", value) do
    if Kino.SmartCell.valid_variable_name?(value) do
      %{"variable" => value}
    else
      %{"variable" => fields["variable"]}
    end
  end

  defp to_updates(_fields, field, value), do: %{field => value}

  @default_keys ["type", "variable"]

  @impl true
  def to_attrs(%{assigns: %{fields: fields}}) do
    connection_keys =
      case fields["type"] do
        "sqlite" ->
          ["database_path"]

        "bigquery" ->
          ~w|project_id default_dataset_id private_key_id private_key client_email client_id|

        type when type in ["postgres", "mysql"] ->
          ~w|database hostname port username password|
      end

    Map.take(fields, @default_keys ++ connection_keys)
  end

  @impl true
  def to_source(attrs) do
    attrs |> to_quoted() |> Kino.SmartCell.quoted_to_string()
  end

  defp to_quoted(%{"type" => "sqlite"} = attrs) do
    quote do
      opts = [database: unquote(attrs["database_path"])]

      {:ok, unquote(quoted_var(attrs["variable"]))} = Kino.start_child({Exqlite, opts})
    end
  end

  defp to_quoted(%{"type" => "postgres"} = attrs) do
    quote do
      opts = unquote(shared_options(attrs))

      {:ok, unquote(quoted_var(attrs["variable"]))} = Kino.start_child({Postgrex, opts})
    end
  end

  defp to_quoted(%{"type" => "mysql"} = attrs) do
    quote do
      opts = unquote(shared_options(attrs))

      {:ok, unquote(quoted_var(attrs["variable"]))} = Kino.start_child({MyXQL, opts})
    end
  end

  defp to_quoted(%{"type" => "bigquery"} = attrs) do
    quote do
      scopes = ["https://www.googleapis.com/auth/cloud-platform"]

      credentials = %{
        "project_id" => unquote(attrs["project_id"]),
        "private_key_id" => unquote(attrs["private_key_id"]),
        "private_key" => unquote(ensure_break_line(attrs["private_key"])),
        "client_email" => unquote(attrs["client_email"]),
        "client_id" => unquote(attrs["client_id"])
      }

      goth_opts = [
        name: Goth,
        http_client: &Req.request/1,
        source: {:service_account, credentials, scopes: scopes}
      ]

      opts = [
        goth: Goth,
        project_id: unquote(attrs["project_id"]),
        default_dataset_id: unquote(attrs["default_dataset_id"])
      ]

      unquote(quoted_var(attrs["variable"])) = ReqBigQuery.attach(Req.new(), opts)

      {:ok, _goth_pid} = Kino.start_child({Goth, goth_opts})
    end
  end

  defp shared_options(attrs) do
    quote do
      [
        hostname: unquote(attrs["hostname"]),
        port: unquote(attrs["port"]),
        username: unquote(attrs["username"]),
        password: unquote(attrs["password"]),
        database: unquote(attrs["database"])
      ]
    end
  end

  defp quoted_var(string), do: {String.to_atom(string), [], nil}

  defp ensure_break_line(string), do: String.replace(string, "\\n", "\n")

  defp default_db_type() do
    cond do
      Code.ensure_loaded?(Postgrex) -> "postgres"
      Code.ensure_loaded?(MyXQL) -> "mysql"
      Code.ensure_loaded?(Exqlite) -> "sqlite"
      Code.ensure_loaded?(ReqBigQuery) -> "bigquery"
      true -> "postgres"
    end
  end

  defp missing_dep(%{"type" => "postgres"}) do
    unless Code.ensure_loaded?(Postgrex) do
      ~s/{:postgrex, "~> 0.16.3"}/
    end
  end

  defp missing_dep(%{"type" => "mysql"}) do
    unless Code.ensure_loaded?(MyXQL) do
      ~s/{:myxql, "~> 0.6.2"}/
    end
  end

  defp missing_dep(%{"type" => "sqlite"}) do
    unless Code.ensure_loaded?(Exqlite) do
      ~s/{:exqlite, "~> 0.11.0"}/
    end
  end

  defp missing_dep(%{"type" => "bigquery"}) do
    unless Code.ensure_loaded?(ReqBigQuery) do
      ~s/{:req_bigquery, github: "livebook-dev\/req_bigquery"}/
    end
  end

  defp missing_dep(_ctx), do: nil
end
