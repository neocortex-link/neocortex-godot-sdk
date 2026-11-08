# Neocortex SDK for Godot

Smart NPCs and virtual assistants for Godot 4. Your characters talk and listen, speak each line in its own emotion, act on what they decide, notice what is around them, chat in groups, and host quizzes.

Version 0.2.0, for Godot 4.7 or later.

## Install

1. Download the [latest release](https://github.com/neocortex-link/neocortex-godot-sdk/releases/latest) (Source code, zip)
2. and copy its `addons/neocortex-godot-sdk` folder into your project's `addons` folder, creating `addons` if you don't have one.
4. Project > Project Settings > Plugins: enable **Neocortex**.
5. For voice input: Project Settings > Audio > Driver > **Enable Input**.
6. In the **Neocortex** dock (next to the Inspector), paste your API key and press Save. Get a key at [neocortex.link/dashboard/api-keys](https://neocortex.link/dashboard/api-keys).

Your key is saved in `addons/neocortex-godot-sdk/neocortex_settings.tres`. Add that file to your `.gitignore`. An exported game carries the key, as with any client side SDK, so ship a key you are happy to ship.

## Try the samples

Run `addons/neocortex-godot-sdk/samples/neocortex_samples.tscn`. Above the samples, pick your character, the question set for the Quiz Show, and your microphone; every sample uses them.

1. **Text Chat**: type to a character; each line is voiced in its own emotion.
2. **Audio Chat**: talk through the microphone, with voice detection or push to talk.
3. **Actions**: ask the character to dance or jump.
4. **Interactables**: the character sees the shapes on the floor and walks to them.
5. **Group Chat**: three characters in one conversation, joining and leaving (Pro or Team plan).
6. **Usage Gating**: check credits and limits before every message.
7. **Quiz Show**: a character hosts a quiz for one to four players (Team plan, and a question set).

Press Escape, or Back to Samples, to return to the list.

## Quick start

The fastest way: open a scene and pick **Project > Tools > Neocortex > Complete Text Chat** (or Complete Voice Chat). Select the new agent, choose your character in the `character_id` dropdown, and run the scene.

From code:

```gdscript
@onready var agent: NeocortexSmartAgent = $NeocortexSmartAgent

func _ready() -> void:
	agent.chat_line_started.connect(func(line: NeocortexChatLine):
		print(line.text, " (", NeocortexEnums.emotion_to_string(line.emotion), ")"))
	agent.request_error.connect(func(error: NeocortexApiError):
		if error.is_retryable():
			print("Busy, try again in a moment")
		elif error.is_out_of_credits():
			print("Out of credits"))
	agent.text_to_text("Hello there!")
```

## What's included

| Node or class | What it does |
| --- | --- |
| `NeocortexSmartAgent` | One character. `text_to_text`, `text_to_audio`, `audio_to_text`, `audio_to_audio`. Replies arrive as lines, each with its emotion; `chat_lines_mode` picks a voice per line, one clip, text only, or the whole reply at once. Speech streams as it is generated. Register actions with `register_action(keyword, handler)`; `action_trigger` sets when they run. |
| `NeocortexGroupDirector` | Up to three characters in one conversation: `send`, `send_to`, `continue_scene`, `send_audio`, and `add_agent` / `remove_agent` while it runs. Needs a Pro or Team plan. |
| `NeocortexQuizAgent` | A character hosts a quiz from a question set: `begin`, `say`, `choose`, `pass_turn`, and `say_as` / `choose_as` for several players. The server handles order, retries, hints and scoring. |
| `NeocortexUsageGate` | Credits and per player or per character limits as flags and signals. Free to call, cached. |
| `NeocortexInteractable` | Marks a 3D object the character can see; actions can target it by id. |
| `NeocortexEventLogger` | Recent gameplay events, sent with each message as context. |
| `NeocortexAudioReceiver` | The microphone, with voice detection or push to talk. |
| `NeocortexFaceAnimator` | Lip sync on ARKit style mouth blend shapes. |
| `NeocortexChatUI`, `NeocortexGroupChatUI`, `NeocortexQuizUI` | Connect a chat panel, text and voice inputs and a thinking indicator to an agent, a group or a quiz. |
| `ApiRequest` | Every API endpoint as an awaitable call, for when you want full control. |

## Editor tools

- **Neocortex dock** and **Project > Tools > Neocortex > Settings...**: your key, your account, and your characters and question sets. Copy an id, or press Use to put it on the selected node. The settings open by themselves the first time a project has no key.
- **Project > Tools > Neocortex**: add a complete text or voice chat, or a single widget, to the open scene; open the samples; open the documentation.
- **Inspector**: character and question set dropdowns on the agents, a warning when there is no key, an interactable's id, a microphone picker.
- **Debugger > Neocortex**: while your game runs from the editor, live microphone levels and what each character is doing.

## Lines and voice

| `chat_lines_mode` | Shows | Plays | Audio credits |
| --- | --- | --- | --- |
| `PER_LINE_AUDIO` (default) | each line as it is spoken | each line in its own emotion | about one per line |
| `SINGLE_AUDIO` | lines one after another | one clip for the reply | one |
| `TEXT` | lines at reading pace | nothing | none |
| `OFF` | the whole reply in `chat_response_received` | nothing (`text_to_audio` raises `audio_response_received`) | one with `text_to_audio` |

In the voiced modes the agent checks your credits first (a free call, cached for 30 s): when they are gone it shows text only, and when they are low it voices the reply as one clip.

`stream_replies` (experimental) streams the reply itself, so the first line is spoken while the rest is still being written; `text_delta` carries the text as it arrives.

## Handling errors

Every component raises `request_failed(message)` and `request_error(NeocortexApiError)`. The error has the HTTP `status`, the API's `code`, and helpers:

| Status and code | Helper | Meaning |
| --- | --- | --- |
| 401 | `is_unauthorized()` | Missing or invalid API key |
| 402 `insufficient_credits` | `is_out_of_credits()` | Your team is out of credits |
| 403 | `is_forbidden()` | Key inactive, a higher plan needed, or not a team member |
| 429 `rate_limit_exceeded` | `is_rate_limited()` | Too many requests; slow down |
| 429 `player_credit_limit`, `character_credit_limit` | `is_out_of_credits()` | A limit set on the key was reached |
| 502 `speech_failed` | `is_speech_failure()` | The voice failed; the text still shows |
| 502 `transcription_failed` | `is_transcription_failure()` | Speech recognition failed |
| 503 `database_unavailable` | `is_retryable()` | Busy; try again in a few seconds |
| 504 `upstream_timeout` | `is_retryable()` | The answer took too long; try again |

Lookups, history and audio are retried once automatically when the error is retryable (`ApiRequest.retry_attempts`). Messages are never resent for you: check `is_retryable()` and send again if you want to.

## Styling the widgets

The widgets in `addons/neocortex-godot-sdk/nodes/` use `NeocortexTheme.tres`: dark pills with amber outlines and accents. Edit it, or set your own `theme` on a widget, to restyle them. The bubble colours are on `NeocortexChatPanel`.

## Upgrading from 0.1

0.2 moves to the Neocortex API v3 and renames several nodes and signals. See [CHANGELOG.md](CHANGELOG.md).

## License

Apache License 2.0, see [LICENSE](LICENSE). If you redistribute the SDK or a modified version of it, keep the attribution in [NOTICE](NOTICE).
