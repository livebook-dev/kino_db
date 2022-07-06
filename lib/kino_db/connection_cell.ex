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
      "credentials" => attrs["credentials"] || %{},
      "access_key_id" => attrs["access_key_id"] || "",
      "secret_access_key" => attrs["secret_access_key"] || "",
      "region" => attrs["region"] || "",
      "output_location" => attrs["output_location"] || ""
    }

    {:ok,
     assign(ctx, fields: fields, missing_dep: missing_dep(fields), help_box: help_box(fields))}
  end

  @impl true
  def handle_connect(ctx) do
    payload = %{
      fields: ctx.assigns.fields,
      missing_dep: ctx.assigns.missing_dep,
      help_box: ctx.assigns.help_box
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
          ~w|project_id default_dataset_id credentials|

        "athena" ->
          ~w|access_key_id secret_access_key region output_location database|

        type when type in ["postgres", "mysql"] ->
          ~w|database hostname port username password|
      end

    Map.take(fields, @default_keys ++ connection_keys)
  end

  @impl true
  def to_source(attrs) do
    required_keys =
      case attrs["type"] do
        "sqlite" ->
          ["database_path"]

        "bigquery" ->
          ~w|project_id|

        "athena" ->
          ~w|access_key_id secret_access_key region output_location database|

        type when type in ["postgres", "mysql"] ->
          ~w|hostname port|
      end

    if required_fields_filled?(attrs, required_keys) do
      attrs |> to_quoted() |> Kino.SmartCell.quoted_to_string()
    else
      ""
    end
  end

  defp required_fields_filled?(attrs, keys) do
    not Enum.any?(keys, fn key -> attrs[key] in [nil, ""] end)
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
    goth_opts_block = check_bigquery_credentials(attrs)

    conn_block =
      quote do
        {:ok, _pid} = Kino.start_child({Goth, opts})

        unquote(quoted_var(attrs["variable"])) =
          Req.new(http_errors: :raise)
          |> ReqBigQuery.attach(
            goth: ReqBigQuery.Goth,
            project_id: unquote(attrs["project_id"]),
            default_dataset_id: unquote(attrs["default_dataset_id"])
          )

        :ok
      end

    join_quoted([goth_opts_block, conn_block])
  end

  defp check_bigquery_credentials(attrs) do
    case attrs["credentials"] do
      %{"type" => "service_account"} ->
        quote do
          credentials = unquote(Macro.escape(attrs["credentials"]))

          opts = [
            name: ReqBigQuery.Goth,
            http_client: &Req.request/1,
            source: {:service_account, credentials}
          ]
        end

      %{"type" => "authorized_user"} ->
        quote do
          credentials = unquote(Macro.escape(attrs["credentials"]))

          opts = [
            name: ReqBigQuery.Goth,
            http_client: &Req.request/1,
            source: {:refresh_token, credentials}
          ]
        end

      _empty_map ->
        quote do
          opts = [name: ReqBigQuery.Goth, http_client: &Req.request/1]
        end
    end
  end

  defp to_quoted(%{"type" => "athena"} = attrs) do
    quote do
      unquote(quoted_var(attrs["variable"])) =
        Req.new(http_errors: :raise)
        |> ReqAthena.attach(
          access_key_id: unquote(attrs["access_key_id"]),
          secret_access_key: unquote(attrs["secret_access_key"]),
          region: unquote(attrs["region"]),
          database: unquote(attrs["database"]),
          output_location: unquote(attrs["output_location"])
        )

      :ok
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

  defp default_db_type() do
    cond do
      Code.ensure_loaded?(Postgrex) -> "postgres"
      Code.ensure_loaded?(MyXQL) -> "mysql"
      Code.ensure_loaded?(Exqlite) -> "sqlite"
      Code.ensure_loaded?(ReqBigQuery) -> "bigquery"
      Code.ensure_loaded?(ReqAthena) -> "athena"
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
      ~s|{:req_bigquery, "~> 0.1.0"}|
    end
  end

  defp missing_dep(%{"type" => "athena"}) do
    unless Code.ensure_loaded?(ReqAthena) do
      ~s|{:req_athena, "~> 0.1.0"}|
    end
  end

  defp missing_dep(_ctx), do: nil

  defp join_quoted(quoted_blocks) do
    asts =
      Enum.flat_map(quoted_blocks, fn
        {:__block__, _meta, nodes} -> nodes
        node -> [node]
      end)

    case asts do
      [node] -> node
      nodes -> {:__block__, [], nodes}
    end
  end

  defp help_box(%{"type" => "bigquery"}) do
    if Code.ensure_loaded?(Mint.HTTP) do
      if running_on_google_metadata?() do
        "You are running inside Google Cloud. Uploading the credentials above is optional."
      else
        ~s|You must upload your Google BigQuery Credentials (<a href="https://cloud.google.com/iam/docs/creating-managing-service-account-keys" target="_blank">find them here</a>) or authenticate your machine with <strong>gcloud</strong> CLI authentication.|
      end
    end
  end

  defp help_box(_ctx), do: nil

  defp running_on_google_metadata? do
    with {:ok, conn} <- Mint.HTTP.connect(:http, "metadata.google.internal", 80),
         {:ok, _} <- Mint.HTTP.set_mode(conn, :passive),
         do: true,
         else: (_ -> false)
  end
end
