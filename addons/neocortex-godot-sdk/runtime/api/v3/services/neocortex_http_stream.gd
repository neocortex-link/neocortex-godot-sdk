class_name NeocortexHttpStream
extends Node

## One HTTP request whose body is handed over as it arrives, for the endpoint that
## streams: /v3/audio/stream (a WAV header, then PCM chunks). HTTPRequest only hands
## over a finished body, so this drives an HTTPClient itself, polling once per frame.
##
## Usage: add it to the tree, connect the signals, call open(). It frees itself once
## finished unless keep_alive is set.

## The response status line and headers arrived. Only 2xx bodies are streamed.
signal response_started(status: int, response_headers: PackedStringArray)
## A piece of a 2xx body.
signal chunk_received(bytes: PackedByteArray)
## The request is over. `error` is null on success; on a non-2xx answer it carries
## the API's error body, already classified.
signal finished(error: NeocortexApiError)

## Seconds to wait for the response to start, and then between two chunks.
var timeout_seconds: float = 20.0
## Leave the node in the tree after it finishes (it is queue_free'd otherwise).
var keep_alive: bool = false

var _client := HTTPClient.new()
var _method: int = HTTPClient.METHOD_POST
var _path: String = "/"
var _headers := PackedStringArray()
var _body := PackedByteArray()
var _url: String = ""
var _requested := false
var _status: int = 0
var _started := false
var _done := false
var _error_body := PackedByteArray()
var _last_activity_ms: int = 0
var _cancelled := false

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

## True once finished has been raised.
func is_done() -> bool:
	return _done

## True when cancel() ended it.
func was_cancelled() -> bool:
	return _cancelled

## Starts the request. Must be in the tree.
func open(url: String, method: int, request_headers: PackedStringArray, body: PackedByteArray) -> void:
	_url = url
	_method = method
	_body = body
	_headers = request_headers.duplicate()
	if not body.is_empty():
		_headers.append("Content-Length: %d" % body.size())

	var regex := RegEx.create_from_string("^(https?)://([^/:]+)(?::(\\d+))?(/.*)?$")
	var parts := regex.search(url)
	if parts == null:
		_fail_local("Invalid URL: %s" % url)
		return

	var tls := parts.get_string(1) == "https"
	var host := parts.get_string(2)
	var port := int(parts.get_string(3)) if not parts.get_string(3).is_empty() else (443 if tls else 80)
	_path = parts.get_string(4) if not parts.get_string(4).is_empty() else "/"

	var err := _client.connect_to_host(host, port, TLSOptions.client() if tls else null)
	if err != OK:
		_fail_local("Could not connect to the server (error %d)." % err)
		return

	_last_activity_ms = Time.get_ticks_msec()
	set_process(true)

## Stops the request. finished is raised with a cancelled error.
func cancel() -> void:
	if _done:
		return
	_cancelled = true
	_client.close()
	var error := NeocortexApiError.new()
	error.cancelled = true
	error.url = _url
	error.message = "Cancelled."
	_finish(error)

func _process(_delta: float) -> void:
	if _done:
		return

	_client.poll()
	var status := _client.get_status()

	match status:
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING:
			_check_timeout()
		HTTPClient.STATUS_CONNECTED:
			if not _requested:
				var err := _client.request_raw(_method, _path, _headers, _body)
				if err != OK:
					_fail_local("Failed to send the request (error %d)." % err)
					return
				_requested = true
				_last_activity_ms = Time.get_ticks_msec()
			elif _started or _client.has_response():
				# A keep alive connection comes back here once the body is read.
				_begin_response()
				_end_body()
			else:
				_check_timeout()
		HTTPClient.STATUS_BODY:
			_begin_response()
			var read_any := false
			while true:
				var chunk := _client.read_response_body_chunk()
				if chunk.is_empty():
					break
				read_any = true
				_handle_chunk(chunk)
				if _done:
					return
			if read_any:
				_last_activity_ms = Time.get_ticks_msec()
			else:
				_check_timeout()
		HTTPClient.STATUS_DISCONNECTED, HTTPClient.STATUS_CONNECTION_ERROR:
			# A body without a length ends when the server closes the connection.
			if _started:
				_end_body()
			else:
				_fail_local("The connection failed.")
		HTTPClient.STATUS_CANT_RESOLVE:
			_fail_local("Could not resolve the server address.")
		HTTPClient.STATUS_CANT_CONNECT:
			_fail_local("Could not connect to the server.")
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_fail_local("The secure connection could not be established.")

func _begin_response() -> void:
	if _started:
		return
	_started = true
	_status = _client.get_response_code()
	_last_activity_ms = Time.get_ticks_msec()
	response_started.emit(_status, _client.get_response_headers())

func _handle_chunk(chunk: PackedByteArray) -> void:
	if _status >= 200 and _status < 300:
		chunk_received.emit(chunk)
	else:
		_error_body.append_array(chunk)

func _end_body() -> void:
	if _status >= 200 and _status < 300:
		_finish(null)
		return
	var error := _make_error(_status, _error_body, "", false)
	_finish(error)

func _check_timeout() -> void:
	if timeout_seconds <= 0.0:
		return
	if Time.get_ticks_msec() - _last_activity_ms > int(timeout_seconds * 1000.0):
		_client.close()
		_finish(_make_error(0, PackedByteArray(), "The request timed out after %ds." % int(timeout_seconds), true))

func _fail_local(message: String) -> void:
	_finish(_make_error(0, PackedByteArray(), message, false))

func _make_error(status: int, body: PackedByteArray, transport_error: String, timed_out: bool) -> NeocortexApiError:
	var error := NeocortexApiError.new()
	error.status = status
	error.timed_out = timed_out
	error.url = _url
	var json := NeocortexJson.parse_object(body)
	error.code = NeocortexJson.get_string(json, "code")
	var api_message := NeocortexJson.get_string(json, "error")
	if not api_message.is_empty():
		error.message = api_message
	else:
		error.message = WebRequest.describe_failure(body.get_string_from_utf8(), status, transport_error)
	return error

func _finish(error: NeocortexApiError) -> void:
	if _done:
		return
	_done = true
	set_process(false)
	_client.close()
	finished.emit(error)
	if not keep_alive:
		queue_free()
