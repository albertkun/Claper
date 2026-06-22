defmodule Claper.WordClouds.WordCloudEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer(),
          word: String.t(),
          word_cloud_id: integer(),
          user_id: integer() | nil,
          attendee_identifier: String.t() | nil,
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  schema "word_cloud_entries" do
    field :word, :string
    field :attendee_identifier, :string

    belongs_to :word_cloud, Claper.WordClouds.WordCloud
    belongs_to :user, Claper.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:word, :word_cloud_id, :user_id, :attendee_identifier])
    |> validate_required([:word, :word_cloud_id])
    |> validate_length(:word, min: 1, max: 50)
  end
end
