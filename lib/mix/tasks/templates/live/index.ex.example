defmodule FrameworkWeb.PageLive.Index do
  use FrameworkWeb, :live_view

  require Logger

  alias FrameworkWeb.PageLive.Index.Context

  @impl true
  def handle_params(params, _uri, socket) do
    if connected?(socket) do
      Context.pubsub_subscribe(socket)
    end

    {:ok, assigns} = Context.page_data(params, socket)

    {:noreply, assign(socket, assigns)}
  end

  # PubSub

  @impl true
  def handle_info({:example, assigns}, socket) do
    {:noreply, assign(socket, assigns)}
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  # User events

  @impl true
  def handle_event("example", params, socket) do
    {:ok, assigns} = Context.page_data(params, socket)

    Context.pubsub_publish(socket, {:example, assigns})

    {:noreply, assign(socket, assigns)}
  end
end
