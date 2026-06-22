defmodule ClaperWeb.WordCloudLive.FormComponent do
  use ClaperWeb, :live_component

  alias Claper.WordClouds

  @impl true
  def update(%{word_cloud: word_cloud} = assigns, socket) do
    changeset = WordClouds.change_word_cloud(word_cloud)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"word_cloud" => params}, socket) do
    changeset =
      socket.assigns.word_cloud
      |> WordClouds.change_word_cloud(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event("save", %{"word_cloud" => params}, socket) do
    save_word_cloud(socket, socket.assigns.live_action, params)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case WordClouds.get_word_cloud_for_event(id, socket.assigns.presentation_file.event_id) do
      nil ->
        {:noreply, socket}

      word_cloud ->
        {:ok, _} = WordClouds.delete_word_cloud(socket.assigns.event_uuid, word_cloud)
        {:noreply, push_navigate(socket, to: socket.assigns.return_to)}
    end
  end

  defp save_word_cloud(socket, :edit, params) do
    case WordClouds.update_word_cloud(
           socket.assigns.event_uuid,
           socket.assigns.word_cloud,
           params
         ) do
      {:ok, _word_cloud} ->
        {:noreply, push_navigate(socket, to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_word_cloud(socket, :new, params) do
    case WordClouds.create_word_cloud(
           params
           |> Map.put("presentation_file_id", socket.assigns.presentation_file.id)
           |> Map.put("position", socket.assigns.position)
           |> Map.put("enabled", false)
         ) do
      {:ok, _word_cloud} ->
        {:noreply, push_navigate(socket, to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end
end
