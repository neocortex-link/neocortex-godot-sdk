# Changelog

## 0.2.0

Moves the SDK to the Neocortex API v3 and adds group conversations, quizzes, actions with targets, streamed speech, new editor tools and a new set of samples.

### Added
- **Group conversations** with `NeocortexGroupDirector`: up to three characters in one conversation. The director picks who speaks, or `send_to` addresses one character; `continue_scene` lets them talk among themselves; `send_audio` takes the player's voice; characters can join and leave while it runs.
- **Quizzes** with `NeocortexQuizAgent` and `NeocortexQuizUI`: a character hosts a quiz from a question set, for one player or several, with typed answers, tapped options, hints, passes, scores, and `resync` after a lost turn.
- **Chat lines**: replies arrive as lines, each with its emotion (`chat_line_started`, `emotion_changed`, `composing_next_line`, `reply_finished`). `chat_lines_mode` picks a voice per line, one clip, text only, or the whole reply. Voiced modes check your credits first.
- **Actions with targets**: several actions per reply, each with a `target_id`; `register_action(keyword, handler)` on the agent; `action_trigger` decides when they run; `actions_completed`.
- **Streamed speech**: the voice starts playing while the rest is still being generated.
- **Streamed replies** (experimental): `stream_replies` and `text_delta`, so the first line is spoken while the reply is still being written.
- **Perception**: interactables carry an id, properties and an optional character id, and the agent sends its own position, with radius and count limits.
- **Conversation Flows**: `flow_state` on every reply.
- **History**: `request_chat_history(limit, before)` pages through past conversations; `load_history_on_start` restores them.
- **Errors you can act on**: every component raises `request_error(NeocortexApiError)` with the status, the API's code and helpers such as `is_retryable()` and `is_out_of_credits()`. Lookups, history and audio retry once on their own. Requests time out (30 s for messages, 20 s for audio, 15 s for lookups), and `abort()` cancels one.
- **Lip sync** with `NeocortexFaceAnimator`, on ARKit style mouth blend shapes.
- **Chat widgets**: `NeocortexChatUI` and `NeocortexGroupChatUI`; bubbles with names, avatars and colours; a typing bubble; a round voice widget; a theme (`NeocortexTheme.tres`) you can restyle.
- **Editor tools**: the Neocortex dock and Settings window (your key, account, characters and question sets, with Copy and Use); Project > Tools > Neocortex to add a complete chat or a single widget; character and question set dropdowns, warnings and a microphone picker in the inspector; a Debugger > Neocortex tab with live microphone levels and what each character is doing.
- **Samples**: seven scenes and a launcher, starring Cora, with her animations and lip sync. Pick one of your characters in the launcher and every sample uses it.
- Apache License 2.0.

### Changed
- All requests go to `https://api.neocortex.link/v3`.
- Settings live in `addons/neocortex-godot-sdk/neocortex_settings.tres`. A key saved by 0.1 is picked up once.
- `NeocortexChatResponse.actions` holds `NeocortexChatAction` objects (`action_names()` gives the keywords). `NeocortexChatResponse.beats` is now `lines`.
- `audio_response_received` passes an `AudioStream`.
- The microphone choice is saved in `user://`, and the recording bus is created when missing.
- Recordings are trimmed of the silence before and after speech, keeping pauses and dropping clicks.
- The player id comes from `NeocortexSessionManager.get_player_id()`.
- `NeocortexActionQueue` handlers receive `(action, response)`. New code should use `register_action()` on the agent.

### Removed
- `request_beats`, `BeatsMode` and `NeocortexBeat`: use chat lines.
- `NeocortexChatMessage`: use `NeocortexChatHistoryEntry`.

## 0.1.0

First release: smart agent, text and voice, beats, usage gate, action queue, event logger, interactables, microphone with voice detection, chat widgets, Arabic text support.
