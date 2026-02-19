defmodule FrameworkWeb.PageLive.Index.Context do
  @moduledoc """
  Context module for page data and business logic.

  Handles data fetching and processing for the page channel.
  Separates business logic from the channel layer to improve
  testability and maintainability.
  """
  require Logger

  # PubSub

  def pubsub_topic(_socket) do
    "page"
  end

  def pubsub_subscribe(socket) do
    Phoenix.PubSub.subscribe(Framework.PubSub, pubsub_topic(socket))
  end

  def pubsub_publish(socket, event) do
    Phoenix.PubSub.broadcast(Framework.PubSub, pubsub_topic(socket), event)
  end

  # Data

  def page_data(_params \\ %{}, _socket) do
    {:ok, example_data} = example_data_fetch()

    page_data = %{example_data: example_data}

    {:ok, page_data}
  end

  # Helpers

  def example_data_fetch() do
    {:ok, DateTime.utc_now()}
  end

  def log_error_then_return(error, value) do
    Logger.error("[#{__MODULE__}] Error: #{inspect(error)}")
    value
  end
end
