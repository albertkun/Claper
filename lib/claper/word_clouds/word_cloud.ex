defmodule Claper.WordClouds.WordCloud do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer(),
          title: String.t(),
          position: integer() | nil,
          enabled: boolean() | nil,
          presentation_file_id: integer() | nil,
          entries: [Claper.WordClouds.WordCloudEntry.t()],
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  @derive {Jason.Encoder, only: [:title, :position]}
  schema "word_clouds" do
    field :title, :string
    field :position, :integer
    field :enabled, :boolean

    belongs_to :presentation_file, Claper.Presentations.PresentationFile

    has_many :entries, Claper.WordClouds.WordCloudEntry, on_replace: :delete

    timestamps()
  end

  @doc false
  def changeset(word_cloud, attrs) do
    word_cloud
    |> cast(attrs, [:title, :presentation_file_id, :position, :enabled])
    |> validate_required([:title, :presentation_file_id, :position])
    |> validate_length(:title, max: 255)
  end
end
