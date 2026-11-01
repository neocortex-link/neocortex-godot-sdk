class_name NeocortexAudioChatInput
extends HBoxContainer

## Voice input UI: a disc that swells with the microphone level, a state disc (a
## microphone while listening, a clock while the character answers) ringed by the
## silence countdown, and, in push to talk mode, a hold to talk button in its place.
## Drives a NeocortexAudioReceiverBase.

@export var audio_receiver: NeocortexAudioReceiverBase

var _amplitude_bar: Control
var _waiting_bar: Range
var _push_to_talk_button: NeocortexPushToTalkButton
var _chat_state: Control
var _recording_icon: CanvasItem
var _waiting_icon: CanvasItem
var _push_to_talk_active := false
var _applied_push_to_talk := false
var _recording := true

func _ready() -> void:
	_amplitude_bar = get_node_or_null("AudioAmplitude/Background/AmplitudeBar")
	_waiting_bar = get_node_or_null("ChatState/WaitingBar")
	_push_to_talk_button = get_node_or_null("PushToTalkButton")
	_chat_state = get_node_or_null("ChatState")
	_recording_icon = get_node_or_null("ChatState/MicIcon")
	_waiting_icon = get_node_or_null("ChatState/ClockIcon")

	if _push_to_talk_button:
		_push_to_talk_button.pushed.connect(_on_push)
		_push_to_talk_button.released.connect(_on_release)

	if audio_receiver == null:
		push_warning("[Neocortex] NeocortexAudioChatInput has no audio_receiver assigned.")
		return
	_apply_mode.call_deferred()

## Points the widget at a receiver after it is ready (the chat UIs do this).
func set_audio_receiver(receiver: NeocortexAudioReceiverBase) -> void:
	audio_receiver = receiver
	if is_node_ready():
		_apply_mode()

## Shows whether the mic is open (true) or the character is busy answering (false).
func set_chat_state(is_recording: bool) -> void:
	_recording = is_recording
	if _recording_icon:
		_recording_icon.visible = is_recording
	if _waiting_icon:
		_waiting_icon.visible = not is_recording
	if _chat_state:
		_chat_state.tooltip_text = "Listening" if is_recording else "Waiting for the reply"
	if _push_to_talk_button:
		_push_to_talk_button.disabled = not is_recording

func _apply_mode() -> void:
	if audio_receiver == null:
		return
	var use_ptt := audio_receiver.use_push_to_talk
	_applied_push_to_talk = use_ptt
	_push_to_talk_active = false
	if _chat_state:
		_chat_state.visible = not use_ptt
	if _push_to_talk_button:
		_push_to_talk_button.visible = use_ptt
	if not use_ptt and not audio_receiver.is_listening():
		audio_receiver.start_microphone()
	set_chat_state(_recording)

func _process(_delta: float) -> void:
	if audio_receiver == null:
		return
	# Re-applied live when the receiver switches mode.
	if audio_receiver.use_push_to_talk != _applied_push_to_talk:
		_apply_mode()
	if audio_receiver.use_push_to_talk and not _push_to_talk_active:
		return

	var level := clampf(audio_receiver.amplitude * 5.0, 0.1, 1.0)
	if _amplitude_bar:
		_amplitude_bar.pivot_offset = _amplitude_bar.size / 2.0
		_amplitude_bar.scale = _amplitude_bar.scale.lerp(Vector2(level, level), 0.1)
	if _waiting_bar:
		_waiting_bar.max_value = maxf(0.01, audio_receiver.max_wait_time)
		_waiting_bar.value = audio_receiver.elapsed_wait_time

func _on_push() -> void:
	if not _push_to_talk_active and audio_receiver != null:
		audio_receiver.start_microphone()
		_push_to_talk_active = true

func _on_release() -> void:
	if _push_to_talk_active and audio_receiver != null:
		audio_receiver.stop_microphone()
		_push_to_talk_active = false
