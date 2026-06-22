defmodule Claper.WordClouds do
  @moduledoc """
  The WordClouds context.
  """

  import Ecto.Query, warn: false
  alias Claper.Repo

  alias Claper.WordClouds.WordCloud
  alias Claper.WordClouds.WordCloudEntry

  def list_word_clouds(presentation_file_id) do
    from(w in WordCloud,
      where: w.presentation_file_id == ^presentation_file_id,
      order_by: [asc: w.id, asc: w.position]
    )
    |> Repo.all()
  end

  def list_word_clouds_at_position(presentation_file_id, position) do
    from(w in WordCloud,
      where: w.presentation_file_id == ^presentation_file_id and w.position == ^position,
      order_by: [asc: w.id]
    )
    |> Repo.all()
  end

  def get_word_cloud!(id), do: Repo.get!(WordCloud, id)

  def get_word_cloud_for_event(id, event_id) do
    from(w in WordCloud,
      join: pf in assoc(w, :presentation_file),
      where: w.id == ^id and pf.event_id == ^event_id
    )
    |> Repo.one()
  end

  def get_word_cloud_current_position(presentation_file_id, position) do
    from(w in WordCloud,
      where:
        w.position == ^position and w.presentation_file_id == ^presentation_file_id and
          w.enabled == true
    )
    |> Repo.one()
  end

  def create_word_cloud(attrs \\ %{}) do
    %WordCloud{}
    |> WordCloud.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, word_cloud} ->
        word_cloud = Repo.preload(word_cloud, presentation_file: :event)
        broadcast({:ok, word_cloud, word_cloud.presentation_file.event.uuid}, :word_cloud_created)

      {:error, changeset} ->
        {:error, %{changeset | action: :insert}}
    end
  end

  def update_word_cloud(event_uuid, %WordCloud{} = word_cloud, attrs) do
    word_cloud
    |> WordCloud.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, word_cloud} ->
        broadcast({:ok, word_cloud, event_uuid}, :word_cloud_updated)

      {:error, changeset} ->
        {:error, %{changeset | action: :update}}
    end
  end

  def delete_word_cloud(event_uuid, %WordCloud{} = word_cloud) do
    {:ok, word_cloud} = Repo.delete(word_cloud)
    broadcast({:ok, word_cloud, event_uuid}, :word_cloud_deleted)
  end

  def change_word_cloud(%WordCloud{} = word_cloud, attrs \\ %{}) do
    WordCloud.changeset(word_cloud, attrs)
  end

  def disable_all(presentation_file_id, position) do
    from(w in WordCloud,
      where: w.presentation_file_id == ^presentation_file_id and w.position == ^position
    )
    |> Repo.update_all(set: [enabled: false])
  end

  def set_enabled(id) do
    get_word_cloud!(id)
    |> Ecto.Changeset.change(enabled: true)
    |> Repo.update()
  end

  def set_disabled(id) do
    get_word_cloud!(id)
    |> Ecto.Changeset.change(enabled: false)
    |> Repo.update()
  end

  @doc """
  Returns all entries for a given word cloud as a frequency map.
  """
  def get_word_frequencies(word_cloud_id) do
    from(e in WordCloudEntry, where: e.word_cloud_id == ^word_cloud_id)
    |> Repo.all()
    |> Enum.group_by(&String.downcase(&1.word))
    |> Enum.map(fn {word, entries} -> {word, length(entries)} end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
  end

  @doc """
  Returns entries submitted by a specific user or attendee for a word cloud.
  """
  def get_entries(user_id, word_cloud_id) when is_integer(user_id) do
    from(e in WordCloudEntry,
      where: e.word_cloud_id == ^word_cloud_id and e.user_id == ^user_id
    )
    |> Repo.all()
  end

  def get_entries(attendee_identifier, word_cloud_id) do
    from(e in WordCloudEntry,
      where:
        e.word_cloud_id == ^word_cloud_id and
          e.attendee_identifier == ^attendee_identifier
    )
    |> Repo.all()
  end

  @doc """
  Adds a word entry to a word cloud and broadcasts the update.
  """
  def add_entry(event_uuid, word_cloud_id, attrs) do
    %WordCloudEntry{}
    |> WordCloudEntry.changeset(Map.put(attrs, "word_cloud_id", word_cloud_id))
    |> Repo.insert()
    |> case do
      {:ok, _entry} ->
        word_cloud = get_word_cloud!(word_cloud_id)
        broadcast({:ok, word_cloud, event_uuid}, :word_cloud_updated)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp broadcast({:ok, word_cloud, event_uuid}, event) do
    Phoenix.PubSub.broadcast(
      Claper.PubSub,
      "event:#{event_uuid}",
      {event, word_cloud}
    )

    {:ok, word_cloud}
  end
end
