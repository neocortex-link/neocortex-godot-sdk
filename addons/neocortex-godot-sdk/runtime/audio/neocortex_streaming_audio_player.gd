class_name NeocortexStreamingAudioPlayer
extends RefCounted

## Plays speech that is still being generated: samples are queued as they arrive and
## pushed into an AudioStreamGenerator, and playback starts once there is enough of a
## head start to stay ahead of the network.
##
## Works with an AudioStreamPlayer, AudioStreamPlayer2D or AudioStreamPlayer3D. Call
## tick() once per frame while a line plays (wait_until_finished() does it for you).

## Longest reply that is buffered. A voiced reply runs to a few seconds.
const CAPACITY_SECONDS := 60.0
## How much audio must be buffered before playback starts.
const PREBUFFER_SECONDS := 0.15
## Size of the generator's own ring buffer.
const GENERATOR_BUFFER_SECONDS := 0.5

var _player: Node
var _sample_rate: int = 0
var _channels: int = 1
## Every sample received, interleaved. Kept so to_wav() can hand the line over whole.
var _samples := PackedFloat32Array()
## How many frames have been pushed into the generator so far.
var _pushed_frames: int = 0
var _complete := false
var _started := false
var _stopped := false
var _overflowed := false
var _drain_deadline_ms: int = -1
var _capacity_frames: int = 0
var _playback: AudioStreamGeneratorPlayback

func _init(player: Node) -> void:
	_player = player

## True once playback started, whether or not it has finished.
func has_started() -> bool:
	return _started

## True once the whole line has arrived and been heard (or nothing ever played).
func is_finished() -> bool:
	if not _complete:
		return false
	if not _started or _stopped:
		return true
	return _drain_deadline_ms >= 0 and Time.get_ticks_msec() >= _drain_deadline_ms

## Seconds of audio received so far.
func buffered_seconds() -> float:
	if _sample_rate <= 0:
		return 0.0
	return float(_samples.size()) / _channels / _sample_rate

## Prepares for a line. Called when the format is known, before any samples.
func begin(sample_rate: int, channels: int) -> void:
	_sample_rate = sample_rate if sample_rate > 0 else 24000
	_channels = channels if channels > 0 else 1
	_samples = PackedFloat32Array()
	_pushed_frames = 0
	_complete = false
	_started = false
	_stopped = false
	_overflowed = false
	_drain_deadline_ms = -1

## Appends audio. Dropped when begin() has not been called yet.
func feed(samples: PackedFloat32Array) -> void:
	if _sample_rate <= 0 or samples.is_empty():
		return

	var room := int(CAPACITY_SECONDS * _sample_rate) * _channels - _samples.size()
	if room <= 0:
		if not _overflowed:
			_overflowed = true
			push_warning("[Neocortex] Streamed reply exceeded %d seconds; the rest is not played." % int(CAPACITY_SECONDS))
		return

	var usable := mini(samples.size(), room)
	# Writes stay on frame boundaries; a half frame would swap the channels after it.
	usable -= usable % _channels
	if usable <= 0:
		return
	_samples.append_array(samples.slice(0, usable) if usable < samples.size() else samples)

## Marks the end of the audio, so playback can stop when the queue runs dry.
func complete() -> void:
	_complete = true

## Drives playback: starts once enough is buffered and keeps the generator fed.
func tick() -> void:
	if _stopped or _sample_rate <= 0 or not is_instance_valid(_player):
		return

	var total_frames := _samples.size() / _channels

	if not _started:
		var prebuffer := int(ceil(PREBUFFER_SECONDS * _sample_rate))
		if total_frames >= prebuffer or (_complete and total_frames > 0):
			_start()
		else:
			return

	if _playback == null:
		return

	var available := _playback.get_frames_available()
	var to_push := mini(available, total_frames - _pushed_frames)
	if to_push > 0:
		var frames := PackedVector2Array()
		frames.resize(to_push)
		for i in to_push:
			var index := (_pushed_frames + i) * _channels
			var left := _samples[index]
			var right := _samples[index + 1] if _channels > 1 else left
			frames[i] = Vector2(left, right)
		_playback.push_buffer(frames)
		_pushed_frames += to_push

	# Everything is queued: the line ends when what is left in the generator drains.
	if _complete and _pushed_frames >= total_frames and _drain_deadline_ms < 0:
		var queued := maxi(0, _capacity_frames - _playback.get_frames_available())
		_drain_deadline_ms = Time.get_ticks_msec() + int(float(queued) / _sample_rate * 1000.0) + 60

## Drives playback until the line has been heard or still_valid returns false.
func wait_until_finished(tree: SceneTree, still_valid: Callable) -> void:
	while still_valid.call():
		tick()
		if is_finished():
			return
		await tree.process_frame

## The audio actually received, as one clip, for listeners that want the whole line.
func to_wav() -> AudioStreamWAV:
	if _samples.is_empty() or _sample_rate <= 0:
		return null
	var data := PackedByteArray()
	data.resize(_samples.size() * 2)
	for i in _samples.size():
		data.encode_s16(i * 2, int(clampf(_samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = _sample_rate
	wav.stereo = _channels > 1
	wav.data = data
	return wav

## Stops this line if it is the one playing.
func stop() -> void:
	if _started and not _stopped and is_instance_valid(_player) and _player.stream is AudioStreamGenerator:
		_player.stop()
	_stopped = true
	_complete = true
	_playback = null

func _start() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = _sample_rate
	generator.buffer_length = GENERATOR_BUFFER_SECONDS
	_player.stream = generator
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	_capacity_frames = _playback.get_frames_available() if _playback != null else 0
	_started = true
