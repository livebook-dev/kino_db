defmodule KinoDB.ConnectionCell do
  @moduledoc false

  # A smart cell used to establish connection to a database.

  use Kino.JS, assets_path: "lib/assets/connection_cell"
  use Kino.JS.Live
  use Kino.SmartCell, name: "Database connection"

  @default_port_by_type %{"postgres" => 5432, "mysql" => 3306, "sqlserver" => 1433}

  @impl true
  def init(attrs, ctx) do
    type = attrs["type"] || default_db_type()
    default_port = @default_port_by_type[type]

    password = attrs["password"] || ""
    secret_access_key = attrs["secret_access_key"] || ""

    fields = %{
      "variable" => Kino.SmartCell.prefixed_var_name("conn", attrs["variable"]),
      "type" => type,
      "hostname" => attrs["hostname"] || "localhost",
      "database_path" => attrs["database_path"] || "",
      "port" => attrs["port"] || default_port,
      "use_ipv6" => Map.get(attrs, "use_ipv6", false),
      "use_ssl" => Map.get(attrs, "use_ssl", false),
      "cacertfile" => attrs["cacertfile"] || "",
      "username" => attrs["username"] || "",
      "password" => password,
      "use_password_secret" => Map.has_key?(attrs, "password_secret") || password == "",
      "password_secret" => attrs["password_secret"] || "",
      "database" => attrs["database"] || "",
      "project_id" => attrs["project_id"] || "",
      "default_dataset_id" => attrs["default_dataset_id"] || "",
      "credentials" => attrs["credentials"] || %{},
      "access_key_id" => attrs["access_key_id"] || "",
      "secret_access_key" => secret_access_key,
      "use_secret_access_key_secret" =>
        Map.has_key?(attrs, "secret_access_key_secret") || secret_access_key == "",
      "secret_access_key_secret" => attrs["secret_access_key_secret"] || "",
      "token" => attrs["token"] || "",
      "region" => attrs["region"] || "us-east-1",
      "workgroup" => attrs["workgroup"] || "",
      "output_location" => attrs["output_location"] || "",
      "account" => attrs["account"] || "",
      "schema" => attrs["schema"] || "",
      "instance" => attrs["instance"] || ""
    }

    ctx =
      assign(ctx,
        fields: fields,
        missing_dep: missing_dep(fields),
        help_box: help_box(fields),
        has_aws_credentials: Code.ensure_loaded?(:aws_credentials)
      )

    {:ok, ctx}
  end

  @impl true
  def handle_connect(ctx) do
    payload = %{
      fields: ctx.assigns.fields,
      missing_dep: ctx.assigns.missing_dep,
      help_box: ctx.assigns.help_box,
      has_aws_credentials: ctx.assigns.has_aws_credentials
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
          ~w|database_path|

        "duckdb" ->
          ~w|database_path|

        "bigquery" ->
          ~w|project_id default_dataset_id credentials|

        "athena" ->
          if fields["use_secret_access_key_secret"],
            do:
              ~w|access_key_id secret_access_key_secret token region workgroup output_location database|,
            else:
              ~w|access_key_id secret_access_key token region workgroup output_location database|

        "snowflake" ->
          if fields["use_password_secret"],
            do: ~w|database schema account username password_secret|,
            else: ~w|database schema account username password|

        "sqlserver" ->
          if fields["use_password_secret"],
            do:
              ~w|database hostname port use_ipv6 username password_secret use_ssl cacertfile instance|,
            else:
              ~w|database hostname port use_ipv6 username password use_ssl cacertfile instance|

        "clickhouse" ->
          if fields["use_password_secret"],
            do: ~w|hostname port use_ssl username password_secret database|,
            else: ~w|hostname port use_ssl username password database|

        type when type in ["postgres", "mysql"] ->
          if fields["use_password_secret"],
            do: ~w|database hostname port use_ipv6 use_ssl cacertfile username password_secret|,
            else: ~w|database hostname port use_ipv6 use_ssl cacertfile username password|
      end

    Map.take(fields, @default_keys ++ connection_keys)
  end

  @impl true
  def to_source(attrs) do
    required_keys =
      case attrs["type"] do
        "sqlite" ->
          ~w|database_path|

        "duckdb" ->
          []

        "bigquery" ->
          ~w|project_id|

        "athena" ->
          if Code.ensure_loaded?(:aws_credentials),
            do: ~w|database|,
            else:
              if(Map.has_key?(attrs, "secret_access_key"),
                do: ~w|access_key_id secret_access_key region database|,
                else: ~w|access_key_id secret_access_key_secret region database|
              )

        "snowflake" ->
          if(Map.has_key?(attrs, "password_secret"),
            do: ~w|account username password_secret|,
            else: ~w|account username password|
          )

        "sqlserver" ->
          ~w|hostname port|

        "clickhouse" ->
          ~w|hostname port|

        type when type in ["postgres", "mysql"] ->
          ~w|hostname port|
      end

    conditional_keys =
      case attrs["type"] do
        "athena" -> ~w|workgroup output_location|
        _ -> []
      end

    if all_fields_filled?(attrs, required_keys) and
         any_fields_filled?(attrs, conditional_keys) do
      attrs |> to_quoted() |> Kino.SmartCell.quoted_to_string()
    else
      ""
    end
  end

  defp all_fields_filled?(attrs, keys) do
    not Enum.any?(keys, fn key -> attrs[key] in [nil, ""] end)
  end

  defp any_fields_filled?(_, []), do: true

  defp any_fields_filled?(attrs, keys) do
    Enum.any?(keys, fn key -> attrs[key] not in [nil, ""] end)
  end

  defp trim_opts(opts) do
    Enum.map(opts, fn
      {key, value} when is_binary(value) -> {key, String.trim(value)}
      {key, value} -> {key, value}
    end)
  end

  defp to_quoted(%{"type" => "sqlite"} = attrs) do
    quote do
      opts = [database: unquote(attrs["database_path"])]

      {:ok, unquote(quoted_var(attrs["variable"]))} = Kino.start_child({Exqlite, opts})
    end
  end

  defp to_quoted(%{"type" => "snowflake"} = attrs) do
    var = quoted_var(attrs["variable"])

    quote do
      :ok = Adbc.download_driver!(:snowflake)
      uri = unquote(build_snowflake_uri(attrs))
      {:ok, db} = Kino.start_child({Adbc.Database, driver: :snowflake, uri: uri})
      {:ok, unquote(var)} = Kino.start_child({Adbc.Connection, database: db})
    end
  end

  defp to_quoted(%{"type" => "duckdb"} = attrs) do
    var = quoted_var(attrs["variable"])

    opts =
      case String.trim(attrs["database_path"]) do
        "" -> [driver: :duckdb]
        path -> [driver: :duckdb, path: path]
      end

    quote do
      :ok = Adbc.download_driver!(:duckdb)
      {:ok, db} = Kino.start_child({Adbc.Database, unquote(opts)})
      {:ok, unquote(var)} = Kino.start_child({Adbc.Connection, database: db})
    end
  end

  defp to_quoted(%{"type" => "postgres"} = attrs) do
    quote do
      opts = unquote(trim_opts(shared_options(attrs) ++ postgres_and_mysql_options(attrs)))

      {:ok, unquote(quoted_var(attrs["variable"]))} = Kino.start_child({Postgrex, opts})
    end
  end

  defp to_quoted(%{"type" => "mysql"} = attrs) do
    quote do
      opts = unquote(trim_opts(shared_options(attrs) ++ postgres_and_mysql_options(attrs)))

      {:ok, unquote(quoted_var(attrs["variable"]))} = Kino.start_child({MyXQL, opts})
    end
  end

  defp to_quoted(%{"type" => "sqlserver"} = attrs) do
    quote do
      opts = unquote(trim_opts(shared_options(attrs) ++ sqlserver_options(attrs)))

      {:ok, unquote(quoted_var(attrs["variable"]))} = Kino.start_child({Tds, opts})
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

  defp to_quoted(%{"type" => "athena"} = attrs) do
    quote do
      unquote(quoted_var(attrs["variable"])) =
        Req.new(http_errors: :raise)
        |> ReqAthena.attach(
          format: :explorer,
          access_key_id: unquote(attrs["access_key_id"]),
          database: unquote(attrs["database"]),
          output_location: unquote(attrs["output_location"]),
          region: unquote(attrs["region"]),
          secret_access_key: unquote(quoted_access_key(attrs)),
          token: unquote(attrs["token"]),
          workgroup: unquote(attrs["workgroup"])
        )

      :ok
    end
  end

  defp to_quoted(%{"type" => "clickhouse"} = attrs) do
    trimmed = attrs |> trim_opts() |> Map.new()
    shared_opts = shared_options(trimmed)

    clickhouse_opts = trimmed |> clickhouse_options(shared_opts)

    quote do
      unquote(quoted_var(attrs["variable"])) = ReqCH.new(unquote(clickhouse_opts))

      :ok
    end
  end

  defp quoted_access_key(%{"secret_access_key" => password}), do: password

  defp quoted_access_key(%{"secret_access_key_secret" => ""}), do: ""

  defp quoted_access_key(%{"secret_access_key_secret" => secret}) do
    quote do
      System.fetch_env!(unquote("LB_#{secret}"))
    end
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

  defp shared_options(attrs) do
    opts = [
      hostname: attrs["hostname"],
      port: attrs["port"],
      username: attrs["username"],
      password: quoted_pass(attrs),
      database: attrs["database"]
    ]

    if attrs["use_ipv6"] do
      opts ++ [socket_options: [:inet6]]
    else
      opts
    end
  end

  defp postgres_and_mysql_options(attrs) do
    if attrs["use_ssl"] do
      cacertfile = attrs["cacertfile"]

      ssl_opts =
        if cacertfile && cacertfile != "" do
          [cacertfile: cacertfile]
        else
          [cacerts: quote(do: :public_key.cacerts_get())]
        end

      [ssl: ssl_opts]
    else
      []
    end
  end

  defp sqlserver_options(attrs) do
    opts =
      if attrs["use_ssl"] do
        cacertfile = attrs["cacertfile"]

        ssl_opts =
          if cacertfile && cacertfile != "" do
            [cacertfile: cacertfile]
          else
            [cacerts: quote(do: :public_key.cacerts_get())]
          end

        [ssl: true, ssl_opts: ssl_opts]
      else
        []
      end

    instance = attrs["instance"]

    if instance && instance != "" do
      opts ++ [instance: instance]
    else
      opts
    end
  end

  defp clickhouse_options(attrs) do
    scheme = if attrs["use_ssl"], do: "https", else: "http"

    [scheme: scheme]
  end

  defp clickhouse_options(attrs, shared_options) do
    attrs
    |> clickhouse_options()
    |> build_clickhouse_base_url(shared_options)
    |> maybe_add_req_basic_auth(shared_options)
    |> maybe_add_clickhouse_database(shared_options)
  end

  defp build_clickhouse_base_url(opts, shared_opts) do
    host = Keyword.fetch!(shared_opts, :hostname)
    port = Keyword.fetch!(shared_opts, :port)
    scheme = Keyword.fetch!(opts, :scheme)

    uri = %URI{scheme: scheme, port: port, host: host}

    opts
    |> Keyword.put_new(:base_url, URI.to_string(uri))
    |> Keyword.delete(:scheme)
  end

  defp maybe_add_req_basic_auth(opts, shared_opts) do
    username = shared_opts[:username]

    if username != "" do
      password = shared_opts[:password]

      auth =
        if is_binary(password) do
          "#{username}:#{password}"
        else
          quote do
            unquote(username) <> ":" <> unquote(password)
          end
        end

      Keyword.put_new(opts, :auth, {:basic, auth})
    else
      opts
    end
  end

  defp maybe_add_clickhouse_database(opts, shared_opts) do
    if shared_opts[:database] != "" do
      Keyword.put_new(opts, :database, shared_opts[:database])
    else
      opts
    end
  end

  defp quoted_var(string), do: {String.to_atom(string), [], nil}

  defp quoted_pass(%{"password" => password}), do: password

  defp quoted_pass(%{"password_secret" => ""}), do: ""

  defp quoted_pass(%{"password_secret" => secret}) do
    quote do
      System.fetch_env!(unquote("LB_#{secret}"))
    end
  end

  defp default_db_type() do
    cond do
      Code.ensure_loaded?(Postgrex) -> "postgres"
      Code.ensure_loaded?(MyXQL) -> "mysql"
      Code.ensure_loaded?(Exqlite) -> "sqlite"
      Code.ensure_loaded?(ReqBigQuery) -> "bigquery"
      Code.ensure_loaded?(ReqAthena) -> "athena"
      Code.ensure_loaded?(ReqCH) -> "clickhouse"
      Code.ensure_loaded?(Adbc) -> "duckdb"
      Code.ensure_loaded?(Tds) -> "sqlserver"
      true -> "postgres"
    end
  end

  defp missing_dep(%{"type" => "postgres"}) do
    unless Code.ensure_loaded?(Postgrex) do
      ~s/{:postgrex, "~> 0.18"}/
    end
  end

  defp missing_dep(%{"type" => "mysql"}) do
    unless Code.ensure_loaded?(MyXQL) do
      ~s/{:myxql, "~> 0.7"}/
    end
  end

  defp missing_dep(%{"type" => "sqlite"}) do
    unless Code.ensure_loaded?(Exqlite) do
      ~s/{:exqlite, "~> 0.11"}/
    end
  end

  defp missing_dep(%{"type" => "bigquery"}) do
    unless Code.ensure_loaded?(ReqBigQuery) do
      ~s|{:req_bigquery, "~> 0.1"}|
    end
  end

  defp missing_dep(%{"type" => "athena"}) do
    missing_many_deps([
      {ReqAthena, ~s|{:req_athena, "~> 0.1"}|},
      {Explorer, ~s|{:explorer, "~> 0.9"}|}
    ])
  end

  defp missing_dep(%{"type" => adbc}) when adbc in ~w[snowflake duckdb] do
    unless Code.ensure_loaded?(Adbc) do
      ~s|{:adbc, "~> 0.3"}|
    end
  end

  defp missing_dep(%{"type" => "sqlserver"}) do
    unless Code.ensure_loaded?(Tds) do
      ~s|{:tds, "~> 2.3"}|
    end
  end

  defp missing_dep(%{"type" => "clickhouse"}) do
    missing_many_deps([
      {ReqCH, ~s|{:req_ch, "~> 0.1"}|},
      {Explorer, ~s|{:explorer, "~> 0.10"}|}
    ])
  end

  defp missing_dep(_ctx), do: nil

  defp missing_many_deps(deps) do
    deps = for {module, dep} <- deps, not Code.ensure_loaded?(module), do: dep

    if deps != [] do
      Enum.join(deps, ", ")
    end
  end

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

  defp help_box(%{"type" => "athena"}) do
    if Code.ensure_loaded?(:aws_credentials) do
      "You must fill in the fields above accordingly or authenticate your machine with AWS CLI authentication."
    end
  end

  defp help_box(_ctx), do: nil

  defp running_on_google_metadata? do
    with {:ok, conn} <- Mint.HTTP.connect(:http, "metadata.google.internal", 80),
         {:ok, _} <- Mint.HTTP.set_mode(conn, :passive),
         do: true,
         else: (_ -> false)
  end

  defp build_snowflake_uri(attrs), do: build_snowflake_uri(attrs, quoted_pass(attrs))

  defp build_snowflake_uri(attrs, password) when is_binary(password) do
    "#{attrs["username"]}:#{password}@#{attrs["account"]}"
    |> build_database_and_schema(attrs)
  end

  defp build_snowflake_uri(%{"username" => username, "account" => account} = attrs, password) do
    rest = build_database_and_schema("@#{account}", attrs)

    quote do
      unquote("#{username}:") <> unquote(password) <> unquote(rest)
    end
  end

  defp build_database_and_schema(uri, %{"database" => ""}), do: uri

  defp build_database_and_schema(uri, %{"database" => database, "schema" => ""}),
    do: "#{uri}/#{database}"

  defp build_database_and_schema(uri, %{"database" => database, "schema" => schema}),
    do: "#{uri}/#{database}/#{schema}"
end
