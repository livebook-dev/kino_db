results = [
  Postgrex.Result,
  MyXQL.Result,
  Exqlite.Result,
  ReqBigQuery.Result,
  ReqAthena.Result,
  Tds.Result
]

for mod <- results do
  defimpl Kino.Render, for: mod do
    def to_livebook(result) do
      result
      |> Kino.DataTable.new(name: "Results")
      |> Kino.Render.to_livebook()
    end
  end
end
