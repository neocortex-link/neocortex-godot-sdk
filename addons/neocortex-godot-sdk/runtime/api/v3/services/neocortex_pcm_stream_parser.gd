class_name NeocortexPcmStreamParser
extends RefCounted

## Reads a streamed WAV body and hands over samples as they arrive, so a voice line
## starts playing while the rest of it is still being synthesized.
##
## The header declares an unknown length, since the server cannot know the size
## until synthesis ends. A header split across chunks is accumulated, and a sample
## split across two chunks is carried over rather than dropped.

## Raised once with the sample rate and channel count, before any samples.
signal format_received(sample_rate: int, channels: int)
## Raised per chunk with the samples decoded from it, -1.0 to 1.0, interleaved.
signal samples_received(samples: PackedFloat32Array)

const HEADER_MIN_BYTES := 44

var sample_rate: int = 0
var channels: int = 0
## The body as text. Only meaningful when is_not_audio() is true.
var raw_text: String = ""

var _header_parsed := false
var _header_rejected := false
var _header_scan := PackedByteArray()
var _carry := PackedByteArray()

## True when the body was not a WAV at all, which means the server sent an error instead.
func is_not_audio() -> bool:
	return _header_rejected

func is_header_parsed() -> bool:
	return _header_parsed

func feed(data: PackedByteArray) -> void:
	if data.is_empty():
		return
	if _header_rejected:
		raw_text += data.get_string_from_utf8()
		return
	if not _header_parsed:
		_consume_header(data)
		return
	_emit_samples(data)

## Call when the body has ended. A body too short to hold a header never was audio.
func complete() -> void:
	if not _header_parsed and not _header_rejected and not _header_scan.is_empty():
		_header_rejected = true
		raw_text = _header_scan.get_string_from_utf8()

func _consume_header(data: PackedByteArray) -> void:
	_header_scan.append_array(data)

	if _header_scan.size() >= 4 and _header_scan.slice(0, 4).get_string_from_ascii() != "RIFF":
		_reject()
		return
	if _header_scan.size() < HEADER_MIN_BYTES:
		return

	var data_offset := _read_format(_header_scan)
	if data_offset < 0:
		# The data chunk may simply not have arrived yet behind a long header.
		if data_offset == -2:
			return
		_reject()
		return

	_header_parsed = true
	format_received.emit(sample_rate, channels)

	if _header_scan.size() > data_offset:
		_emit_samples(_header_scan.slice(data_offset))
	_header_scan = PackedByteArray()

func _reject() -> void:
	_header_rejected = true
	raw_text = _header_scan.get_string_from_utf8()
	_header_scan = PackedByteArray()

## Reads the format chunk and returns where the samples start, -1 when this is not
## 16-bit PCM, or -2 when more header bytes are needed.
func _read_format(header: PackedByteArray) -> int:
	if header.slice(8, 12).get_string_from_ascii() != "WAVE":
		return -1

	var offset := 12
	while offset + 8 <= header.size():
		var chunk_id := header.slice(offset, offset + 4).get_string_from_ascii()
		var chunk_size := header.decode_u32(offset + 4)

		if chunk_id == "fmt ":
			if offset + 24 > header.size():
				return -2
			channels = header.decode_u16(offset + 10)
			sample_rate = header.decode_u32(offset + 12)
			if header.decode_u16(offset + 22) != 16:
				return -1
		elif chunk_id == "data":
			return offset + 8 if sample_rate > 0 and channels > 0 else -1

		# Chunks are word aligned; an odd size carries a pad byte.
		offset += 8 + chunk_size + (chunk_size % 2)

	return -2

func _emit_samples(data: PackedByteArray) -> void:
	_carry.append_array(data)

	# An odd byte at the end is the first half of a sample still in flight.
	var usable := _carry.size() - (_carry.size() % 2)
	if usable <= 0:
		return

	var samples := PackedFloat32Array()
	samples.resize(usable / 2)
	for i in usable / 2:
		samples[i] = float(_carry.decode_s16(i * 2)) / 32768.0

	_carry = _carry.slice(usable)
	samples_received.emit(samples)
