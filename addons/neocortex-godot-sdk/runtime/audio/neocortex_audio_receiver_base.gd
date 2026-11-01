class_name NeocortexAudioReceiverBase
extends Node

## Base for microphone receivers. Concrete receivers capture the mic, emit the recorded
## clip through audio_recorded, and expose live amplitude and silence time for UI.

signal audio_recorded(audio: AudioStreamWAV)
signal recording_failed(error: String)

## Record while a push to talk button is held, instead of by voice activity.
@export var use_push_to_talk: bool = false:
	get:
		return _push_to_talk
	set(value):
		set_push_to_talk(value)
## Input level (0 to 1) above which the player counts as speaking.
@export_range(0.0, 1.0) var amplitude_threshold: float = 0.1
## Seconds of silence after speech that end an utterance.
@export var max_wait_time: float = 1.0

var _push_to_talk := false

## Live input level, 0 to 1.
var amplitude: float = 0.0
## Seconds of continuous silence counted toward max_wait_time.
var elapsed_wait_time: float = 0.0
## True while the player is speaking in the current utterance.
var is_user_speaking: bool = false

## True while the microphone is listening for an utterance.
func is_listening() -> bool:
	return false

func start_microphone() -> void:
	push_error("start_microphone() is not implemented on %s" % get_class())

func stop_microphone() -> void:
	push_error("stop_microphone() is not implemented on %s" % get_class())

## Switches between push to talk and voice activity. Switching to push to talk while
## listening closes the current listen.
func set_push_to_talk(value: bool) -> void:
	_push_to_talk = value

## Trims the recording and emits it. A recording with no speech in it is dropped, and
## in voice activity mode listening resumes.
func emit_recorded_clip(raw: AudioStreamWAV) -> void:
	if raw == null:
		recording_failed.emit("Recording failed.")
		return
	var trimmed := NeocortexAudioUtils.trim(raw)
	if trimmed == null:
		if not use_push_to_talk:
			start_microphone()
		return
	audio_recorded.emit(trimmed)
