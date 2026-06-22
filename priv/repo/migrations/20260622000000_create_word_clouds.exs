defmodule Claper.Repo.Migrations.CreateWordClouds do
  use Ecto.Migration

  def change do
    create table(:word_clouds) do
      add :title, :string, null: false
      add :position, :integer, null: false
      add :enabled, :boolean, default: false, null: false
      add :presentation_file_id, references(:presentation_files, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create index(:word_clouds, [:presentation_file_id])
    create index(:word_clouds, [:presentation_file_id, :position])

    create table(:word_cloud_entries) do
      add :word, :string, null: false
      add :word_cloud_id, references(:word_clouds, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all)
      add :attendee_identifier, :string

      timestamps()
    end

    create index(:word_cloud_entries, [:word_cloud_id])
    create index(:word_cloud_entries, [:word_cloud_id, :user_id])
    create index(:word_cloud_entries, [:word_cloud_id, :attendee_identifier])
  end
end
