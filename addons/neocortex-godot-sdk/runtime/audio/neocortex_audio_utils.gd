class_name NeocortexAudioUtils
extends RefCounted

## Audio helpers: encode an AudioStreamWAV to a RIFF/WAV byte buffer (for the
## transcription endpoint), trim the silence around a recording, and decode the speech
## the API returns.

## A sound shorter than this, between its first and last loud sample, is a click.
const MIN_SPEECH_SECONDS := 0.2
## Silence kept before the first and after the last sound, so words are not clipped.
const TRIM_MARGIN_SECONDS := 0.25
## Recordings are padded to at least this long; very short clips transcribe badly.
const MIN_CLIP_SECONDS := 1.0

## Wraps a 16-bit PCM AudioStreamWAV's samples in a canonical RIFF/WAV header.
static func encode_wav(stream: AudioStreamWAV) -> PackedByteArray:
	var data := stream.data
	var channels := 2 if stream.stereo else 1
	var bits := _bits_per_sample(stream.format)
	var sample_rate := stream.mix_rate

	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false

	buffer.put_data("RIFF".to_ascii_buffer())
	buffer.put_u32(36 + data.size())
	buffer.put_data("WAVE".to_ascii_buffer())

	buffer.put_data("fmt ".to_ascii_buffer())
	buffer.put_u32(16)
	buffer.put_u16(1)
	buffer.put_u16(channels)
	buffer.put_u32(sample_rate)
	buffer.put_u32(sample_rate * channels * bits / 8)
	buffer.put_u16(channels * bits / 8)
	buffer.put_u16(bits)

	buffer.put_data("data".to_ascii_buffer())
	buffer.put_u32(data.size())
	buffer.put_data(data)

	return buffer.data_array

## Cuts the silence before the first and after the last sound, keeping a margin on both
## sides and every pause in between. Returns null when there is no sound at all or only
## a click. Pads the result to at least MIN_CLIP_SECONDS.
static func trim(stream: AudioStreamWAV, threshold: float = 0.001, margin: float = TRIM_MARGIN_SECONDS) -> AudioStreamWAV:
	if stream == null:
		return null
	if _bits_per_sample(stream.format) != 16:
		return stream # only 16-bit PCM is supported; pass through untouched

	var channels := 2 if stream.stereo else 1
	var samples := _decode_s16(stream.data)
	var frames := samples.size() / channels

	var first := -1
	var last := -1
	for i in frames:
		if absf(samples[i * channels]) >= threshold:
			if first < 0:
				first = i
			last = i

	if first < 0:
		return null
	if float(last - first) / stream.mix_rate <= MIN_SPEECH_SECONDS:
		return null

	var margin_frames := int(margin * stream.mix_rate)
	var start := maxi(0, first - margin_frames)
	var end := mini(frames, last + 1 + margin_frames)
	var kept := samples.slice(start * channels, end * channels)

	var min_samples := int(MIN_CLIP_SECONDS * stream.mix_rate) * channels
	if kept.size() < min_samples:
		var pad := min_samples - kept.size()
		var padded := PackedFloat32Array()
		padded.resize(pad)
		kept.append_array(padded)

	var trimmed := AudioStreamWAV.new()
	trimmed.format = AudioStreamWAV.FORMAT_16_BITS
	trimmed.mix_rate = stream.mix_rate
	trimmed.stereo = stream.stereo
	trimmed.data = _encode_s16(kept)
	return trimmed

## Decodes a speech response: a WAV body (RIFF) becomes an AudioStreamWAV, anything
## else is read as MP3. Returns null when it is neither.
static func decode_audio(bytes: PackedByteArray) -> AudioStream:
	if bytes.size() < 4:
		return null
	if bytes.slice(0, 4).get_string_from_ascii() == "RIFF":
		return decode_wav(bytes)
	var mp3 := AudioStreamMP3.load_from_buffer(bytes)
	if mp3 == null or mp3.get_length() <= 0.0:
		return null
	return mp3

## Reads a 16-bit PCM WAV body into an AudioStreamWAV. Returns null when it is not one.
static func decode_wav(bytes: PackedByteArray) -> AudioStreamWAV:
	var parser := NeocortexPcmStreamParser.new()
	var chunks: Array[PackedFloat32Array] = []
	parser.samples_received.connect(func(s): chunks.append(s))
	parser.feed(bytes)
	parser.complete()
	if not parser.is_header_parsed():
		return null

	var all := PackedFloat32Array()
	for chunk in chunks:
		all.append_array(chunk)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = parser.sample_rate
	wav.stereo = parser.channels > 1
	wav.data = _encode_s16(all)
	return wav

## Length in seconds of any clip the SDK produces.
static func length_of(stream: AudioStream) -> float:
	return stream.get_length() if stream != null else 0.0

static func _bits_per_sample(format: int) -> int:
	match format:
		AudioStreamWAV.FORMAT_8_BITS:
			return 8
		_:
			return 16

static func _decode_s16(data: PackedByteArray) -> PackedFloat32Array:
	var count := data.size() / 2
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		out[i] = float(data.decode_s16(i * 2)) / 32768.0
	return out

static func _encode_s16(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size() * 2)
	for i in samples.size():
		out.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	return out
