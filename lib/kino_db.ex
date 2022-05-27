results = [Postgrex.Result, MyXQL.Result, Exqlite.Result]

for mod <- results do
  defimpl Kino.Render, for: mod do
    def to_livebook(result) do
      result
      |> Kino.DataTable.new(name: "Results")
      |> Kino.Render.to_livebook()
    end
  end
end

defimpl Kino.Render, for: Req.Response do
  def to_livebook(%{body: result}) when is_struct(result, ReqBigQuery.Result) do
    result
    |> Kino.DataTable.new(name: "Results")
    |> Kino.Render.to_livebook()
  end

  def to_livebook(response), do: Kino.Output.inspect(response)
end
