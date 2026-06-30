defmodule Claper.Repo.Migrations.AddSurveyModeToPresentationStates do
  use Ecto.Migration

  def change do
    alter table(:presentation_states) do
      add :survey_mode, :boolean, default: false, null: false
    end
  end
end
