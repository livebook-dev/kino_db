defimpl Kino.Render, for: Postgrex.Result do
  def to_livebook(result) do
    result
    |> Kino.DataTable.new(name: "Results")
    |> Kino.Render.to_livebook()
  end
end

defimpl Kino.Render, for: MyXQL.Result do
  def to_livebook(result) do
    result
    |> Kino.DataTable.new(name: "Results")
    |> Kino.Render.to_livebook()
  end
end
