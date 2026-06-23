defmodule ClaperWeb.EventLive.WordCloudComponent do
  use ClaperWeb, :live_component

  alias Claper.WordClouds

  @impl true
  def update(assigns, socket) do
    word_frequencies = WordClouds.get_word_frequencies(assigns.word_cloud.id)
    existing_entries = get_existing_entries(assigns)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:word_frequencies, word_frequencies)
     |> assign(:existing_entries, existing_entries)
     |> assign_new(:word_input, fn -> "" end)
     |> assign_new(:error, fn -> nil end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-gray-900 rounded-2xl p-4 shadow-lg">
      <h3 class="text-white font-bold text-lg mb-1">{@word_cloud.title}</h3>

      <%= if length(@word_frequencies) > 0 do %>
        <div class="flex flex-wrap gap-2 justify-center items-center py-3 min-h-24">
          <%= for {{word, count}, index} <- Enum.with_index(@word_frequencies) do %>
            <span class={"#{font_size_class(count, elem(hd(@word_frequencies), 1))} #{word_color(index)} leading-tight"}>
              {word}
            </span>
          <% end %>
        </div>
      <% else %>
        <div class="flex items-center justify-center py-4 min-h-16">
          <p class="text-gray-500 text-sm italic">{gettext("No words yet. Be the first!")}</p>
        </div>
      <% end %>

      <div class="mt-3 border-t border-gray-700 pt-3">
        <%= if length(@existing_entries) > 0 do %>
          <div class="mb-2 flex flex-wrap gap-1">
            <span class="text-gray-400 text-xs">{gettext("Your words:")}</span>
            <%= for entry <- @existing_entries do %>
              <span class="bg-gray-700 text-white text-xs rounded-full px-2 py-0.5">
                {entry.word}
              </span>
            <% end %>
          </div>
        <% end %>

        <form phx-submit="submit-word" phx-target={@myself} class="flex gap-2">
          <input
            type="text"
            name="word"
            value={@word_input}
            phx-change="update-input"
            phx-target={@myself}
            placeholder={gettext("Type a word...")}
            maxlength="50"
            autocomplete="off"
            class="flex-1 bg-gray-800 text-white rounded-lg px-3 py-2 text-sm border border-gray-600 focus:outline-none focus:border-primary-500 placeholder-gray-500"
          />
          <button
            type="submit"
            class="bg-linear-to-tl from-primary-500 to-secondary-500 text-white px-4 py-2 rounded-lg text-sm font-semibold hover:opacity-90 transition-opacity"
          >
            {gettext("Submit")}
          </button>
        </form>

        <%= if @error do %>
          <p class="text-red-400 text-xs mt-1">{@error}</p>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("submit-word", %{"word" => word}, socket) do
    word = String.trim(word)

    if String.length(word) == 0 do
      {:noreply, assign(socket, :error, gettext("Please enter a word"))}
    else
      attrs = build_entry_attrs(socket, word)

      case WordClouds.add_entry(
             socket.assigns.event.uuid,
             socket.assigns.word_cloud.id,
             attrs
           ) do
        {:ok, _} ->
          word_frequencies = WordClouds.get_word_frequencies(socket.assigns.word_cloud.id)
          existing_entries = get_existing_entries(socket.assigns)

          {:noreply,
           socket
           |> assign(:word_frequencies, word_frequencies)
           |> assign(:existing_entries, existing_entries)
           |> assign(:word_input, "")
           |> assign(:error, nil)}

        {:error, _changeset} ->
          {:noreply, assign(socket, :error, gettext("Word is too long (max 50 characters)"))}
      end
    end
  end

  @impl true
  def handle_event("update-input", %{"word" => word}, socket) do
    {:noreply, assign(socket, :word_input, word)}
  end

  defp get_existing_entries(%{current_user: current_user} = assigns) when is_map(current_user) do
    WordClouds.get_entries(current_user.id, assigns.word_cloud.id)
  end

  defp get_existing_entries(%{attendee_identifier: attendee_identifier} = assigns) do
    WordClouds.get_entries(attendee_identifier, assigns.word_cloud.id)
  end

  defp get_existing_entries(_assigns), do: []

  defp build_entry_attrs(%{assigns: %{current_user: current_user}}, word)
       when is_map(current_user) do
    %{"word" => word, "user_id" => current_user.id}
  end

  defp build_entry_attrs(%{assigns: %{attendee_identifier: attendee_identifier}}, word) do
    %{"word" => word, "attendee_identifier" => attendee_identifier}
  end

  defp font_size_class(count, max_count) do
    ratio = if max_count > 0, do: count / max_count, else: 0

    cond do
      ratio >= 0.8 -> "text-4xl font-black"
      ratio >= 0.6 -> "text-3xl font-bold"
      ratio >= 0.4 -> "text-2xl font-semibold"
      ratio >= 0.2 -> "text-xl font-medium"
      true -> "text-base font-normal"
    end
  end

  defp word_color(index) do
    colors = [
      "text-primary-400",
      "text-secondary-400",
      "text-green-400",
      "text-yellow-400",
      "text-pink-400",
      "text-purple-400",
      "text-blue-400",
      "text-orange-400"
    ]

    Enum.at(colors, rem(index, length(colors)))
  end
end
