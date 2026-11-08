class_name NeocortexAudioReceiver
extends NeocortexAudioReceiverBase

## Microphone receiver with voice activity detection.
##
## Captures the mic through a muted "NeocortexRecord" audio bus carrying an
## AudioEffectRecord (the clip) and an AudioEffectCapture (live amplitude). The bus
## is created at runtime when the project's bus layout has none. In voice mode it
## listens, detects speech by amplitude, and ends the utterance after max_wait_time
## of silence; in push to talk mode start and stop are driven by a button.
## Needs Project Settings > Audio > Driver > Enable Input.

const RECORD_BUS := "NeocortexRecord"
## The bus the SDK 0.1 layout used; still picked up when present.
const LEGACY_RECORD_BUS := "Record"
const AUDIO_SAMPLE_WINDOW := 512
const AMPLITUDE_MULTIPLIER := 10.0
## Speech shorter than this is a cough or a click, not an utterance.
const MIN_SPEECH_SECONDS := 0.15
## Longest utterance kept, in seconds.
const MAX_RECORDING_SECONDS := 29.0

## Leave the input stream running between utterances, so the next one starts with no
## device warm up. Costs a little CPU while idle.
@export var keep_microphone_open: bool = false
## Ask for microphone permission on ready (Android), rather than on first use.
@export var request_permission_on_start: bool = true

signal permission_denied

var _listening := false
var _record_effect: AudioEffectRecord
var _capture_effect: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _speech_seconds := 0.0
var _recorded_seconds := 0.0
var _report_ms := 0

func _ready() -> void:
	if request_permission_on_start:
		NeocortexMicrophone.request_permission()

func is_listening() -> bool:
	return _listening

func set_push_to_talk(value: bool) -> void:
	var changed := _push_to_talk != value
	_push_to_talk = value
	if changed and value and _listening and is_inside_tree():
		_close(false)

## The input devices, for a picker.
func get_microphones() -> PackedStringArray:
	return NeocortexMicrophone.devices()

## Selects an input device by index and remembers it for next time.
func select_microphone(index: int) -> void:
	NeocortexMicrophone.set_selected_index(index)

func start_microphone() -> void:
	if _listening:
		return
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		_fail("Enable Project Settings > Audio > Driver > Enable Input to use the microphone.")
		return
	if not NeocortexMicrophone.request_permission():
		permission_denied.emit()
		_fail("Microphone permission has not been granted.")
		return
	if not _resolve_bus_effects():
		_fail("Could not set up the microphone recording bus.")
		return

	NeocortexMicrophone.apply_selected_device()

	if _mic_player == null:
		_mic_player = AudioStreamPlayer.new()
		_mic_player.stream = AudioStreamMicrophone.new()
		_mic_player.bus = _bus_name()
		add_child(_mic_player)
	if not _mic_player.playing:
		_mic_player.play()

	_capture_effect.clear_buffer()
	_record_effect.set_recording_active(true)

	amplitude = 0.0
	elapsed_wait_time = 0.0
	is_user_speaking = false
	_speech_seconds = 0.0
	_recorded_seconds = 0.0
	_listening = true

# A microphone that cannot start says why in the Output panel, as well as through
# recording_failed.
func _fail(message: String) -> void:
	push_error("[Neocortex] " + message)
	recording_failed.emit(message)

func stop_microphone() -> void:
	_close(true)

func _close(emit: bool) -> void:
	if not _listening:
		return
	var recording := _record_effect.get_recording()
	_record_effect.set_recording_active(false)
	_listening = false
	is_user_speaking = false

	if not keep_microphone_open and _mic_player != null:
		_mic_player.stop()
		_mic_player.queue_free()
		_mic_player = null

	if emit:
		emit_recorded_clip(recording)

func _process(delta: float) -> void:
	_report()
	if not _listening:
		return

	_update_amplitude()
	_recorded_seconds += delta

	if _recorded_seconds >= MAX_RECORDING_SECONDS:
		stop_microphone()
		return
	if use_push_to_talk:
		return

	if amplitude > amplitude_threshold:
		is_user_speaking = true
		_speech_seconds += delta
		elapsed_wait_time = 0.0
	elif is_user_speaking:
		elapsed_wait_time += delta
		if elapsed_wait_time >= max_wait_time:
			elapsed_wait_time = 0.0
			if _speech_seconds < MIN_SPEECH_SECONDS:
				# Too short to be speech: keep listening from here.
				_restart_listen()
			else:
				stop_microphone()

func _restart_listen() -> void:
	_record_effect.set_recording_active(false)
	_record_effect.set_recording_active(true)
	is_user_speaking = false
	_speech_seconds = 0.0
	_recorded_seconds = 0.0

func _update_amplitude() -> void:
	if _capture_effect == null:
		return
	var frames_available := _capture_effect.get_frames_available()
	if frames_available <= 0:
		return
	var buffer := _capture_effect.get_buffer(mini(frames_available, AUDIO_SAMPLE_WINDOW))
	# Older frames are not needed; dropping them keeps the level live.
	_capture_effect.clear_buffer()
	if buffer.is_empty():
		return
	var sum := 0.0
	for frame in buffer:
		sum += absf(frame.x)
	amplitude = clampf(sum / buffer.size() * AMPLITUDE_MULTIPLIER, 0.0, 1.0)

func _bus_name() -> String:
	return LEGACY_RECORD_BUS if AudioServer.get_bus_index(LEGACY_RECORD_BUS) >= 0 else RECORD_BUS

func _resolve_bus_effects() -> bool:
	var bus_index := AudioServer.get_bus_index(_bus_name())
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, RECORD_BUS)
		# Muted, so the player never hears themselves.
		AudioServer.set_bus_mute(bus_index, true)

	_record_effect = null
	_capture_effect = null
	for i in AudioServer.get_bus_effect_count(bus_index):
		var effect := AudioServer.get_bus_effect(bus_index, i)
		if effect is AudioEffectRecord and _record_effect == null:
			_record_effect = effect
		elif effect is AudioEffectCapture and _capture_effect == null:
			_capture_effect = effect

	if _record_effect == null:
		_record_effect = AudioEffectRecord.new()
		AudioServer.add_bus_effect(bus_index, _record_effect)
	if _capture_effect == null:
		_capture_effect = AudioEffectCapture.new()
		AudioServer.add_bus_effect(bus_index, _capture_effect)
	return true

# Live levels for the editor's Debugger > Neocortex tab.
func _report() -> void:
	if not NeocortexDebug.is_active() or Time.get_ticks_msec() < _report_ms:
		return
	_report_ms = Time.get_ticks_msec() + 100
	NeocortexDebug.report("receiver", self, {
		"listening": _listening,
		"speaking": is_user_speaking,
		"push_to_talk": use_push_to_talk,
		"amplitude": amplitude,
		"threshold": amplitude_threshold,
		"wait": elapsed_wait_time,
		"max_wait": max_wait_time,
		"device": AudioServer.input_device,
	})

func _exit_tree() -> void:
	NeocortexDebug.forget(self)
	if _listening and _record_effect != null:
		_record_effect.set_recording_active(false)
	_listening = false
