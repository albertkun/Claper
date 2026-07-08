defmodule ClaperWeb.EventLive.Presenter do
  use ClaperWeb, :live_view

  alias ClaperWeb.Presence
  alias Claper.Embeds.Embed
  alias Claper.Polls.Poll
  alias Claper.Forms.Form
  alias Claper.Quizzes.Quiz
  alias Claper.WordClouds.WordCloud
  alias Claper.Presentations

  @impl true
  def mount(%{"code" => code} = params, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    event =
      Claper.Events.get_event_with_code(code, [
        :user,
        presentation_file: [:polls, :presentation_state]
      ])

    if is_nil(event) || not leader?(socket, event) do
      {:ok,
       socket
       |> put_flash(:error, gettext("Event doesn't exist"))
       |> redirect(to: "/")}
    else
      if connected?(socket) do
        Claper.Events.Event.subscribe(event.uuid)
        Claper.Presentations.subscribe(event.presentation_file.id)
      end

      endpoint_config = Application.get_env(:claper, ClaperWeb.Endpoint)[:url]
      port = endpoint_config[:port]
      scheme = endpoint_config[:scheme]
      host = endpoint_config[:host]
      path = endpoint_config[:path]

      default_ports = [80, 443]
      port_suffix = if port in default_ports, do: "", else: ":" <> Integer.to_string(port)

      host = "#{scheme}://#{host}#{port_suffix}/#{path}"

      socket =
        socket
        |> assign(:attendees_nb, 1)
        |> assign(
          :host,
          host
        )
        |> assign(:event, event)
        |> assign(:iframe, !is_nil(params["iframe"]))
        |> assign(:state, event.presentation_file.presentation_state)
        |> assign(:posts, list_posts(socket, event.uuid))
        |> assign(:pinned_posts, list_pinned_posts(socket, event.uuid))
        |> assign(:show_only_pinned, event.presentation_file.presentation_state.show_only_pinned)
        |> assign(:reacts, [])
        |> assign(:survey_interactions, [])
        |> assign(:survey_word_frequencies, %{})
        |> poll_at_position
        |> form_at_position
        |> embed_at_position
        |> quiz_at_position
        |> word_cloud_at_position
        |> survey_interactions_at_position

      {:ok, socket, temporary_assigns: []}
    end
  end

  defp update_post_in_list(posts, updated_post) do
    Enum.map(posts, fn post ->
      if post.id == updated_post.id, do: updated_post, else: post
    end)
  end

  defp leader?(%{assigns: %{current_user: current_user}} = _socket, event) do
    Claper.Events.led_by?(current_user.email, event) || event.user.id == current_user.id
  end

  defp leader?(_socket, _event), do: false

  @impl true
  def handle_info(%{event: "presence_diff"}, %{assigns: %{event: event}} = socket) do
    attendees = Presence.list("event:#{event.uuid}")
    {:noreply, push_event(socket, "update-attendees", %{count: Enum.count(attendees)})}
  end

  @impl true
  def handle_info({:post_created, post}, socket) do
    {:noreply,
     socket
     |> update(:posts, fn posts -> posts ++ [post] end)}
  end

  @impl true
  def handle_info({:post_pinned, post}, socket) do
    {:noreply,
     socket
     |> update(:pinned_posts, fn pinned_posts -> pinned_posts ++ [post] end)}
  end

  @impl true
  def handle_info({:post_unpinned, post}, socket) do
    {:noreply,
     socket
     |> update(:pinned_posts, fn pinned_posts ->
       Enum.reject(pinned_posts, fn p -> p.id == post.id end)
     end)}
  end

  @impl true
  def handle_info({:state_updated, state}, socket) do
    {:noreply,
     socket
     |> assign(:state, state)
     |> push_event("page", %{current_page: state.position})
     |> push_event("reset-global-react", %{})
     |> poll_at_position
     |> embed_at_position
     |> word_cloud_at_position
     |> survey_interactions_at_position}
  end

  @impl true
  def handle_info({:current_interactions, interactions}, socket) do
    {:noreply,
     socket
     |> assign_survey_interactions(interactions)
     |> assign(:current_poll, nil)
     |> assign(:current_embed, nil)
     |> assign(:current_form, nil)
     |> assign(:current_quiz, nil)
     |> assign(:current_word_cloud, nil)
     |> assign(:word_cloud_frequencies, [])}
  end

  @impl true
  def handle_info({:post_updated, updated_post}, socket) do
    updated_posts = update_post_in_list(socket.assigns.posts, updated_post)
    updated_pinned_posts = update_post_in_list(socket.assigns.pinned_posts, updated_post)

    {:noreply,
     socket
     |> assign(:posts, updated_posts)
     |> assign(:pinned_posts, updated_pinned_posts)}
  end

  @impl true
  def handle_info({:post_deleted, post}, socket) do
    updated_posts = Enum.reject(socket.assigns.posts, fn p -> p.id == post.id end)
    updated_pinned_posts = Enum.reject(socket.assigns.pinned_posts, fn p -> p.id == post.id end)

    {:noreply,
     socket |> assign(:posts, updated_posts) |> assign(:pinned_posts, updated_pinned_posts)}
  end

  @impl true
  def handle_info({:poll_updated, poll}, socket) do
    socket = update_survey_poll(socket, poll)

    if poll.enabled do
      {:noreply,
       socket
       |> update(:current_poll, fn _current_poll -> poll end)}
    else
      {:noreply,
       socket
       |> update(:current_poll, fn _current_poll -> nil end)}
    end
  end

  @impl true
  def handle_info({:poll_deleted, poll}, socket) do
    {:noreply,
     socket
     |> update_survey_poll(%{poll | enabled: false})
     |> update(:current_poll, fn _current_poll -> nil end)}
  end

  @impl true
  def handle_info({:form_updated, form}, socket) do
    if form.enabled do
      {:noreply,
       socket
       |> update(:current_form, fn _current_form -> form end)}
    else
      {:noreply,
       socket
       |> update(:current_form, fn _current_form -> nil end)}
    end
  end

  @impl true
  def handle_info({:form_deleted, _form}, socket) do
    {:noreply,
     socket
     |> update(:current_form, fn _current_form -> nil end)}
  end

  @impl true
  def handle_info({:embed_updated, embed}, socket) do
    if embed.enabled do
      {:noreply,
       socket
       |> update(:current_embed, fn _current_embed -> embed end)}
    else
      {:noreply,
       socket
       |> update(:current_embed, fn _current_embed -> nil end)}
    end
  end

  @impl true
  def handle_info({:embed_deleted, _embed}, socket) do
    {:noreply,
     socket
     |> update(:current_embed, fn _current_embed -> nil end)}
  end

  @impl true
  def handle_info({:quiz_updated, quiz}, socket) do
    {:noreply,
     socket
     |> update(:current_quiz, fn _current_quiz -> quiz end)}
  end

  @impl true
  def handle_info({:quiz_deleted, _quiz}, socket) do
    {:noreply,
     socket
     |> update(:current_quiz, fn _current_quiz -> nil end)}
  end

  @impl true
  def handle_info({:word_cloud_updated, word_cloud}, socket) do
    word_frequencies = Claper.WordClouds.get_word_frequencies(word_cloud.id)

    cond do
      socket.assigns.state.survey_mode ->
        {:noreply, socket |> update_survey_word_cloud(word_cloud, word_frequencies)}

      word_cloud.enabled ->
        {:noreply,
         socket
         |> assign(:current_word_cloud, word_cloud)
         |> assign(:word_cloud_frequencies, word_frequencies)}

      true ->
        {:noreply,
         socket
         |> assign(:current_word_cloud, nil)
         |> assign(:word_cloud_frequencies, [])}
    end
  end

  @impl true
  def handle_info({:word_cloud_deleted, word_cloud}, socket) do
    {:noreply,
     socket
     |> update_survey_word_cloud(%{word_cloud | enabled: false}, [])
     |> assign(:current_word_cloud, nil)
     |> assign(:word_cloud_frequencies, [])}
  end

  @impl true
  def handle_info({:chat_visible, value}, socket) do
    {:noreply,
     socket
     |> push_event("chat-visible", %{value: value})
     |> update(:chat_visible, fn _chat_visible -> value end)}
  end

  @impl true
  def handle_info({:show_only_pinned, value}, socket) do
    {:noreply,
     socket
     |> push_event("show_only_pinned", %{value: value})
     |> update(:show_only_pinned, fn _show_only_pinned -> value end)}
  end

  @impl true
  def handle_info({:poll_visible, value}, socket) do
    {:noreply,
     socket
     |> push_event("poll-visible", %{value: value})
     |> update(:poll_visible, fn _poll_visible -> value end)}
  end

  @impl true
  def handle_info({:join_screen_visible, value}, socket) do
    {:noreply,
     socket
     |> push_event("join-screen-visible", %{value: value})
     |> update(:join_screen_visible, fn _join_screen_visible -> value end)}
  end

  @impl true
  def handle_info({:react, type}, socket) do
    {:noreply,
     socket
     |> push_event("global-react", %{type: type})}
  end

  @impl true
  def handle_info(
        {:current_interaction, %Poll{} = interaction},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:current_poll, interaction)
     |> assign(:current_embed, nil)
     |> assign(:current_form, nil)
     |> assign(:current_quiz, nil)
     |> assign(:current_word_cloud, nil)
     |> assign(:word_cloud_frequencies, [])}
  end

  @impl true
  def handle_info(
        {:current_interaction, %Embed{} = interaction},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:current_embed, interaction)
     |> assign(:current_poll, nil)
     |> assign(:current_form, nil)
     |> assign(:current_quiz, nil)
     |> assign(:current_word_cloud, nil)
     |> assign(:word_cloud_frequencies, [])}
  end

  @impl true
  def handle_info(
        {:current_interaction, %Form{} = interaction},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:current_form, interaction)
     |> assign(:current_poll, nil)
     |> assign(:current_embed, nil)
     |> assign(:current_quiz, nil)
     |> assign(:current_word_cloud, nil)
     |> assign(:word_cloud_frequencies, [])}
  end

  @impl true
  def handle_info(
        {:current_interaction, %Quiz{} = interaction},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:current_quiz, interaction)
     |> assign(:current_poll, nil)
     |> assign(:current_embed, nil)
     |> assign(:current_form, nil)
     |> assign(:current_word_cloud, nil)
     |> assign(:word_cloud_frequencies, [])}
  end

  @impl true
  def handle_info(
        {:current_interaction, %WordCloud{} = interaction},
        socket
      ) do
    word_frequencies = Claper.WordClouds.get_word_frequencies(interaction.id)

    {:noreply,
     socket
     |> assign(:current_word_cloud, interaction)
     |> assign(:word_cloud_frequencies, word_frequencies)
     |> assign(:current_poll, nil)
     |> assign(:current_embed, nil)
     |> assign(:current_form, nil)
     |> assign(:current_quiz, nil)}
  end

  @impl true
  def handle_info(
        {:current_interaction, nil},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:current_poll, nil)
     |> assign(:current_embed, nil)
     |> assign(:current_form, nil)
     |> assign(:current_quiz, nil)
     |> assign(:current_word_cloud, nil)
     |> assign(:word_cloud_frequencies, [])}
  end

  @impl true
  def handle_info(
        {:review_quiz_questions},
        socket
      ) do
    send_update(
      ClaperWeb.EventLive.ManageableQuizComponent,
      id: "#{socket.assigns.current_quiz.id}-quiz",
      current_question_idx: 0
    )

    {:noreply, socket |> assign(:current_question_idx, 0)}
  end

  @impl true
  def handle_info(
        {:next_quiz_question},
        socket
      ) do
    idx =
      if socket.assigns.current_question_idx <
           length(socket.assigns.current_quiz.quiz_questions) - 1,
         do: socket.assigns.current_question_idx + 1,
         else: -1

    send_update(
      ClaperWeb.EventLive.ManageableQuizComponent,
      id: "#{socket.assigns.current_quiz.id}-quiz",
      current_question_idx: idx
    )

    {:noreply, socket |> assign(:current_question_idx, idx)}
  end

  @impl true
  def handle_info(
        {:prev_quiz_question},
        socket
      ) do
    idx =
      if socket.assigns.current_question_idx > 0,
        do: socket.assigns.current_question_idx - 1,
        else: 0

    send_update(
      ClaperWeb.EventLive.ManageableQuizComponent,
      id: "#{socket.assigns.current_quiz.id}-quiz",
      current_question_idx: idx
    )

    {:noreply, socket |> assign(:current_question_idx, idx)}
  end

  @impl true
  def handle_info(_, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
  end

  defp poll_at_position(%{assigns: %{event: event, state: state}} = socket) do
    with poll <-
           Claper.Polls.get_poll_current_position(
             event.presentation_file.id,
             state.position
           ) do
      socket |> assign(:current_poll, poll)
    end
  end

  defp form_at_position(%{assigns: %{event: event, state: state}} = socket) do
    with form <-
           Claper.Forms.get_form_current_position(
             event.presentation_file.id,
             state.position
           ) do
      socket |> assign(:current_form, form)
    end
  end

  defp embed_at_position(%{assigns: %{event: event, state: state}} = socket) do
    with embed <-
           Claper.Embeds.get_embed_current_position(
             event.presentation_file.id,
             state.position
           ) do
      socket |> assign(:current_embed, embed)
    end
  end

  defp quiz_at_position(%{assigns: %{event: event, state: state}} = socket) do
    with quiz <-
           Claper.Quizzes.get_quiz_current_position(
             event.presentation_file.id,
             state.position
           ) do
      socket |> assign(:current_quiz, quiz) |> assign(:current_question_idx, 0)
    end
  end

  defp word_cloud_at_position(%{assigns: %{event: event, state: state}} = socket) do
    word_cloud =
      Claper.WordClouds.get_word_cloud_current_position(
        event.presentation_file.id,
        state.position
      )

    word_frequencies =
      if word_cloud, do: Claper.WordClouds.get_word_frequencies(word_cloud.id), else: []

    socket
    |> assign(:current_word_cloud, word_cloud)
    |> assign(:word_cloud_frequencies, word_frequencies)
  end

  # In survey mode, gather every enabled interaction at the current position so
  # the projected view can display their results side by side.
  defp survey_interactions_at_position(%{assigns: %{event: event, state: state}} = socket) do
    if state.survey_mode do
      interactions = Claper.Interactions.get_active_interactions(event, state.position)
      assign_survey_interactions(socket, interactions)
    else
      socket
      |> assign(:survey_interactions, [])
      |> assign(:survey_word_frequencies, %{})
    end
  end

  # Keeps polls and word clouds (the types with projectable results) and loads
  # the word frequencies for each cloud, keyed by id.
  defp assign_survey_interactions(socket, interactions) do
    interactions =
      interactions
      |> Enum.filter(&(match?(%Poll{}, &1) or match?(%WordCloud{}, &1)))
      |> Enum.map(fn
        %Poll{} = poll -> Claper.Polls.set_percentages(poll)
        other -> other
      end)

    frequencies =
      interactions
      |> Enum.filter(&match?(%WordCloud{}, &1))
      |> Enum.into(%{}, fn wc -> {wc.id, Claper.WordClouds.get_word_frequencies(wc.id)} end)

    socket
    |> assign(:survey_interactions, interactions)
    |> assign(:survey_word_frequencies, frequencies)
  end

  # Replaces a single poll inside the survey list with its updated counterpart.
  # Matches on struct type as well as id since ids collide across types.
  defp update_survey_poll(socket, poll) do
    interactions = socket.assigns[:survey_interactions] || []

    cond do
      not Enum.any?(interactions, &(match?(%Poll{}, &1) and &1.id == poll.id)) ->
        socket

      poll.enabled ->
        assign(
          socket,
          :survey_interactions,
          Enum.map(interactions, fn
            %Poll{id: id} when id == poll.id -> poll
            other -> other
          end)
        )

      true ->
        assign(
          socket,
          :survey_interactions,
          Enum.reject(interactions, &(match?(%Poll{}, &1) and &1.id == poll.id))
        )
    end
  end

  # Same as update_survey_poll but for word clouds, also refreshing the
  # frequencies map used by the projected grid.
  defp update_survey_word_cloud(socket, word_cloud, word_frequencies) do
    interactions = socket.assigns[:survey_interactions] || []

    cond do
      not Enum.any?(interactions, &(match?(%WordCloud{}, &1) and &1.id == word_cloud.id)) ->
        socket

      word_cloud.enabled ->
        socket
        |> assign(
          :survey_interactions,
          Enum.map(interactions, fn
            %WordCloud{id: id} when id == word_cloud.id -> word_cloud
            other -> other
          end)
        )
        |> assign(
          :survey_word_frequencies,
          Map.put(socket.assigns.survey_word_frequencies, word_cloud.id, word_frequencies)
        )

      true ->
        socket
        |> assign(
          :survey_interactions,
          Enum.reject(interactions, &(match?(%WordCloud{}, &1) and &1.id == word_cloud.id))
        )
        |> assign(
          :survey_word_frequencies,
          Map.delete(socket.assigns.survey_word_frequencies, word_cloud.id)
        )
    end
  end

  defp list_posts(_socket, event_id) do
    Claper.Posts.list_posts(event_id, [:event, :reactions])
  end

  defp list_pinned_posts(_socket, event_id) do
    Claper.Posts.list_pinned_posts(event_id, [:event, :reactions])
  end
end
