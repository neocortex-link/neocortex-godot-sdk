class_name WebRequest
extends Node

## Thin HTTP helper the API layer builds on.
##
## Each call gets its own HTTPRequest child, so several requests can run at once.
## Every request has a timeout, `abort()` cancels everything in flight and leaves the
## node usable, and a failure is classified into a NeocortexApiError.

## Raised with a short message for every failure that is not a deliberate cancel.
signal request_failed(error: String)
## Raised alongside request_failed with the classified error.
signal request_error(error: NeocortexApiError)

## How much of an unrecognised error body is worth repeating.
const MAX_ERROR_LENGTH := 200

var progress: float = 0.0
var last_response_code: int = 0
## The last failure's message, or "" after a success.
var last_error: String = ""
## The API's machine readable code for the last failure ("insufficient_credits",
## "quiz_finished"), or "" for a transport failure and anything not from the API.
var last_error_code: String = ""
## The last failure, classified. Null after a success.
var last_api_error: NeocortexApiError = null
## The last request was cancelled on purpose, so its missing response is not a failure.
var was_cancelled: bool = false
var headers: Dictionary = {}

# HTTPRequest -> _Pending, so abort() can finish requests HTTPRequest never will.
var _active: Dictionary = {}

## Bridges HTTPRequest.request_completed and abort(): whichever comes first wins.
class _Pending extends RefCounted:
	signal done(result: Array)
	var finished := false

	func finish(result: Array) -> void:
		if finished:
			return
		finished = true
		done.emit(result)

## Cancels everything this node has in flight. Cancelled requests resolve with
## `cancelled = true` and raise no failure signal.
func abort() -> void:
	for http in _active.keys():
		var pending: _Pending = _active[http]
		if is_instance_valid(http):
			http.cancel_request()
		pending.finish([-1, 0, PackedStringArray(), PackedByteArray()])

## Sends a request and awaits the response.
##
## payload keys:
##   url (String, required)
##   method (int, HTTPClient.METHOD_*; defaults to POST)
##   content_type (String, optional)
##   body (PackedByteArray | String | Dictionary | Array, optional)
##   timeout (float seconds; 0 waits forever, which no API call should do)
##   handled_codes (PackedStringArray: API codes the caller handles, so they are not logged)
##
## Returns { ok: bool, code: int, body: PackedByteArray, headers: PackedStringArray,
##           error: NeocortexApiError (null when ok), cancelled: bool }.
func send_async(payload: Dictionary) -> Dictionary:
	progress = 0.0
	last_response_code = 0
	last_error = ""
	last_error_code = ""
	last_api_error = null
	was_cancelled = false

	var url: String = payload.get("url", "")
	if not is_inside_tree():
		return _finish_failure(payload, 0, PackedByteArray(), "The Neocortex request node is not in the scene tree.", false)

	var http := HTTPRequest.new()
	http.timeout = float(payload.get("timeout", 0.0))
	add_child(http)

	var pending := _Pending.new()
	_active[http] = pending
	http.request_completed.connect(func(result: int, code: int, response_headers: PackedStringArray, body: PackedByteArray):
		pending.finish([result, code, response_headers, body]))

	var request_headers := PackedStringArray()
	for key in headers.keys():
		request_headers.append("%s: %s" % [key, headers[key]])
	if payload.has("content_type"):
		request_headers.append("Content-Type: %s" % payload.content_type)

	var method: int = payload.get("method", HTTPClient.METHOD_POST)
	var body_bytes := _to_bytes(payload.get("body", PackedByteArray()))

	var err := http.request_raw(url, request_headers, method, body_bytes)
	if err != OK:
		_cleanup(http)
		return _finish_failure(payload, 0, PackedByteArray(), "Failed to start the request (error %d)." % err, false)

	var result: Array = await pending.done
	_cleanup(http)

	var http_result: int = result[0]
	var response_code: int = result[1]
	var response_headers: PackedStringArray = result[2]
	var body: PackedByteArray = result[3]
	last_response_code = response_code
	progress = 1.0

	# A caller that cancelled on purpose (the agent moved on, abort() was called) is
	# not an error and must not be logged as one.
	if http_result == -1:
		was_cancelled = true
		var cancelled := NeocortexApiError.new()
		cancelled.cancelled = true
		cancelled.url = url
		cancelled.message = "Cancelled."
		return { "ok": false, "code": 0, "body": PackedByteArray(), "headers": PackedStringArray(), "error": cancelled, "cancelled": true }

	if http_result == HTTPRequest.RESULT_TIMEOUT:
		return _finish_failure(payload, 0, PackedByteArray(), "The request timed out after %ds." % int(http.timeout), true)

	if http_result != HTTPRequest.RESULT_SUCCESS:
		return _finish_failure(payload, response_code, body, _describe_transport(http_result), false)

	if response_code >= 400 or response_code == 0:
		return _finish_failure(payload, response_code, body, "", false)

	return { "ok": true, "code": response_code, "body": body, "headers": response_headers, "error": null, "cancelled": false }

## Builds the classified error for a failed response and records it as the last error.
func make_error(status: int, body: PackedByteArray, transport_error: String, timed_out: bool, url: String) -> NeocortexApiError:
	var error := NeocortexApiError.new()
	error.status = status
	error.timed_out = timed_out
	error.url = url

	var text := body.get_string_from_utf8() if not body.is_empty() else ""
	var json := NeocortexJson.parse_object(body) if text.strip_edges().begins_with("{") else {}
	error.code = NeocortexJson.get_string(json, "code")
	var api_message := NeocortexJson.get_string(json, "error")

	if not api_message.is_empty():
		error.message = api_message
	elif timed_out:
		error.message = transport_error
	else:
		error.message = describe_failure(text, status, transport_error)
	return error

## Turns a failed response body into something a human can read at a glance. A proxy,
## tunnel or captive portal answers with a whole HTML page, so only a short non-markup
## body is worth showing; anything else is reported as its status code.
static func describe_failure(body: String, status: int, transport_error: String) -> String:
	var fallback := ("Request failed (%d)" % status) if status > 0 else "Request failed"
	var text := body.strip_edges().trim_prefix("﻿").strip_edges()

	if text.is_empty():
		return transport_error if not transport_error.is_empty() else fallback
	if text.begins_with("<"):
		return fallback
	if text.length() > MAX_ERROR_LENGTH:
		return text.substr(0, MAX_ERROR_LENGTH).strip_edges() + "..."
	return text

## JSON encodes a Dictionary or Array to UTF-8 bytes.
func get_bytes(payload) -> PackedByteArray:
	return JSON.stringify(payload).to_utf8_buffer()

## Records a failure, logs it unless the caller handles its code, and raises the
## failure signals. Returns the result dictionary send_async hands back.
func _finish_failure(payload: Dictionary, status: int, body: PackedByteArray, transport_error: String, timed_out: bool) -> Dictionary:
	var error := make_error(status, body, transport_error, timed_out, str(payload.get("url", "")))
	last_api_error = error
	last_error = error.message
	last_error_code = error.code
	last_response_code = status

	var handled: PackedStringArray = payload.get("handled_codes", PackedStringArray())
	if error.code.is_empty() or not handled.has(error.code):
		push_error("[Neocortex] %s (%s)" % [error.message, error.url])

	return { "ok": false, "code": status, "body": body, "headers": PackedStringArray(), "error": error, "cancelled": false }

func _describe_transport(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "Could not connect to the server."
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "Could not resolve the server address."
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "The connection failed."
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "The secure connection could not be established."
		HTTPRequest.RESULT_NO_RESPONSE:
			return "The server sent no response."
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "The response was too large."
		_:
			return "The request failed (result %d)." % result

func _to_bytes(body) -> PackedByteArray:
	if body is PackedByteArray:
		return body
	if body is String:
		return body.to_utf8_buffer()
	return JSON.stringify(body).to_utf8_buffer()

func _cleanup(http: HTTPRequest) -> void:
	_active.erase(http)
	if is_instance_valid(http):
		http.queue_free()
