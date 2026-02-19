defmodule Framework.Context.Schema do
  @moduledoc """
  Ecto schema and changesets for Framework.Context.Schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "table_name" do
    # Replace with fields
  end

  @required []
  @castable @required ++ []

  def changeset(record, attrs) do
    record
    |> cast(attrs, @castable)
    |> validate_required(@required)
  end
end
