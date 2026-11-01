class_name NeocortexApiError
extends RefCounted

## A failed request, classified against the v3 error contract so a game can branch
## on what happened rather than on the wording of a message.
##
##   401                         invalid or missing API key
##   402 insufficient_credits    the team is out of credits
##   403                         key inactive, plan required, not a team member
##   429 rate_limit_exceeded,
##       character_credit_limit,
##       player_credit_limit     slow down, or a per-key cap was hit
##   502 speech_failed           speech synthesis failed before any audio was sent
##   502 transcription_failed    speech recognition failed
##   503 database_unavailable    the service is busy; retry in a few seconds
##   504 upstream_timeout        the model did not answer in time; retry
##
## `status` is 0 for a transport failure (no connection, DNS, TLS) and for a local
## timeout; `timed_out` says which.

const INSUFFICIENT_CREDITS := "insufficient_credits"
const CHARACTER_CREDIT_LIMIT := "character_credit_limit"
const PLAYER_CREDIT_LIMIT := "player_credit_limit"
const RATE_LIMIT_EXCEEDED := "rate_limit_exceeded"
const SPEECH_FAILED := "speech_failed"
const TRANSCRIPTION_FAILED := "transcription_failed"
const DATABASE_UNAVAILABLE := "database_unavailable"
const UPSTREAM_TIMEOUT := "upstream_timeout"

## Codes that mean the caller is out of credit, one way or another.
const CREDIT_CODES: PackedStringArray = [INSUFFICIENT_CREDITS, CHARACTER_CREDIT_LIMIT, PLAYER_CREDIT_LIMIT]

## HTTP status, or 0 when the request never got an answer.
var status: int = 0
## The API's machine readable code, or "" when it sent none (or the API never answered).
var code: String = ""
## A short, human readable message, safe to show in a log or a debug label.
var message: String = ""
## The request was cancelled on purpose; not a failure worth showing.
var cancelled: bool = false
## This side gave up waiting.
var timed_out: bool = false
## The URL that failed, for logs.
var url: String = ""

## True when trying the same request again a moment later can succeed.
func is_retryable() -> bool:
	if timed_out:
		return true
	if code == DATABASE_UNAVAILABLE or code == UPSTREAM_TIMEOUT:
		return true
	return status == 503 or status == 504

func is_unauthorized() -> bool:
	return status == 401

func is_forbidden() -> bool:
	return status == 403

func is_out_of_credits() -> bool:
	return status == 402 or CREDIT_CODES.has(code)

func is_rate_limited() -> bool:
	return status == 429 and not CREDIT_CODES.has(code)

func is_speech_failure() -> bool:
	return code == SPEECH_FAILED

func is_transcription_failure() -> bool:
	return code == TRANSCRIPTION_FAILED

func _to_string() -> String:
	return message
