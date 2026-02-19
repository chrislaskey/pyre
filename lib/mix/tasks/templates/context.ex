defmodule Framework.Context do
  @moduledoc """
  Template context module for generated Ecto contexts.

  Do NOT add any use-case specific functions to this file. It is generic on
  purpose. It is the responsibility of the callers to pass the correct `params`
  into the functions. Create use-case specific functions or context modules closer
  to the business logic.
  """

  import Ecto.Query, except: [update: 2]

  alias Framework.Context.Schema

  @default_preloads []
  @default_upsert_get_by_keys [:name]

  @spec list(list()) :: list()
  def list(options \\ []) do
    Schema
    |> preload(^Keyword.get(options, :preload, @default_preloads))
    |> Framework.Repo.all()
  end

  @spec get(binary() | integer(), list()) :: Schema.t() | nil
  def get(id, options \\ []) do
    Schema
    |> preload(^Keyword.get(options, :preload, @default_preloads))
    |> Framework.Repo.get(id)
  end

  @spec get_by(list(), list()) :: Schema.t() | nil
  def get_by(values, options \\ []) do
    Schema
    |> preload(^Keyword.get(options, :preload, @default_preloads))
    |> Framework.Repo.get_by(values)
  end

  @spec fetch(binary() | integer(), list()) :: {:ok, Schema.t()} | {:error, atom()}
  def fetch(id, options \\ []) do
    case get(id, options) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  @spec create(map()) :: {:ok, Schema.t()} | {:error, Ecto.Changeset.t()}
  def create(params) do
    Schema
    |> Schema.changeset(params)
    |> Framework.Repo.insert()
  end

  @spec update(Schema.t(), map()) :: {:ok, Schema.t()} | {:error, Ecto.Changeset.t()}
  def update(record, params) do
    record
    |> Schema.changeset(params)
    |> Framework.Repo.update()
  end

  @spec upsert(Schema.t(), map()) :: {:ok, Schema.t()} | {:error, Ecto.Changeset.t()}
  def upsert(params, options \\ []) do
    params = Recase.Enumerable.stringify_keys(params)

    get_by_keys =
      options
      |> Keyword.get(:keys, @default_upsert_get_by_keys)
      |> Enum.map(fn key ->
        key = to_string(key)
        value = Map.get(params, key)

        {String.to_atom(key), value}
      end)

    case get_by(get_by_keys) do
      nil -> create(params)
      record -> update(record, params)
    end
  end

  @spec delete(Schema.t()) :: {:ok, Schema.t()} | {:error, Ecto.Changeset.t()}
  def delete(record) do
    Framework.Repo.delete(record)
  end
end
