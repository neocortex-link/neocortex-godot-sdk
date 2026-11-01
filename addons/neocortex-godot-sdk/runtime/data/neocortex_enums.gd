class_name NeocortexEnums
extends RefCounted

## Shared enums for the Neocortex SDK.
##
## The server sends emotions in any casing ("happy", "HAPPY") and the audio
## endpoints expect the uppercase form ("HAPPY"), so this file also holds the
## string and enum bridge helpers used across the SDK. Unknown values never throw:
## they fall back to the first member.

enum Emotions {
	NEUTRAL,

	HAPPY,
	PLEASED,
	DISAPPOINTED,
	UPSET,

	AMAZED,
	CURIOUS,
	CONFUSED,
	ALARMED,

	FASCINATED,
	IMPRESSED,
	ANNOYED,
	ANGRY,

	CONFIDENT,
	REASSURED,
	CONCERNED,
	SCARED,
}

## How a NeocortexSmartAgent delivers a reply. Every mode except OFF drops the reply
## in as ordered chat lines; the mode decides the audio.
enum ChatLinesMode {
	PER_LINE_AUDIO, ## Each line is voiced separately, in order. About 1 audio credit PER line.
	SINGLE_AUDIO,   ## Lines drop in while ONE voice clip plays for the whole reply. 1 audio credit.
	TEXT,           ## Lines drop in as messages with an emotion each. No audio, no extra cost.
	OFF,            ## One reply, delivered whole.
}

## When a reply's actions are run.
enum ActionTrigger {
	WHEN_RESPONSE_RECEIVED, ## The instant the reply arrives; the character may act before it speaks.
	WHEN_SPEECH_STARTS,     ## As the character starts speaking.
	AFTER_REPLY_SPOKEN,     ## Once the character has finished speaking the reply.
}

enum EventPriority {
	LOW = 0,
	MEDIUM = 1,
	HIGH = 2,
}

enum InteractableType {
	CHARACTER,
	OBJECT,
}

enum UsageStatus {
	OK,
	LOW,
	EMPTY,
}

enum WritingDirection {
	LEFT_TO_RIGHT,
	RIGHT_TO_LEFT,
}

enum MicrophoneState {
	NOT_ACTIVE = 0,
	BOOTING = 1,
	RECORDING = 2,
}

enum ApiResponseType {
	TEXT,
	AUDIO,
	STREAM,
}

## What the quiz is waiting for. Open the microphone, or show the answer controls,
## while this is anything but NOTHING.
enum QuizExpecting {
	NOTHING,      ## The host is talking, or the quiz is over. Collect nothing.
	ANSWER,       ## An attempt at the question on screen.
	CONFIRMATION, ## A yes or a no, usually to an offer of another try.
}

## How the host read what the player said. Only ANSWER is ever scored.
enum QuizIntent {
	UNCLEAR,
	ANSWER,
	AFFIRM,
	DECLINE,
	REPEAT,
	HINT,
	STOP,
}

## What a host line is doing, so a scene can be timed to it rather than to the turn.
enum QuizLineRole {
	REACTION, ## Responding to what the player said. Also the fallback for an unknown value.
	GREETING,
	QUESTION,
	CLOSING,
}

## How one player's attempt was judged.
enum QuizVerdict {
	UNANSWERED,
	CORRECT,
	PARTIAL,
	INCORRECT,
}

## Why something the player said never reached the quiz host.
enum QuizInputDropReason {
	SUPERSEDED, ## They said something newer before the host was ready. The newer one is sent.
	EXPIRED,    ## It waited too long to still be an answer to what the host asked.
	FINISHED,   ## The run has already ended.
	NO_SESSION, ## The quiz has not been started yet.
	FAILED,     ## The turn it would have been sent on failed.
	BUSY,       ## The host was busy and the agent is set not to hold anything.
}

## Display names aligned to the Emotions enum order.
const EMOTION_NAMES: PackedStringArray = [
	"Neutral",
	"Happy", "Pleased", "Disappointed", "Upset",
	"Amazed", "Curious", "Confused", "Alarmed",
	"Fascinated", "Impressed", "Annoyed", "Angry",
	"Confident", "Reassured", "Concerned", "Scared",
]

## Parses an emotion from any casing the server might send. NEUTRAL for unknown or empty.
static func emotion_from_string(value: String) -> Emotions:
	return parse_enum(Emotions, value, Emotions.NEUTRAL) as Emotions

## Title case name, e.g. Emotions.HAPPY -> "Happy".
static func emotion_to_string(emotion: Emotions) -> String:
	var index := int(emotion)
	if index < 0 or index >= EMOTION_NAMES.size():
		return EMOTION_NAMES[0]
	return EMOTION_NAMES[index]

## Uppercase name the audio endpoints expect, e.g. Emotions.HAPPY -> "HAPPY".
static func emotion_to_upper(emotion: Emotions) -> String:
	return emotion_to_string(emotion).to_upper()

static func usage_status_from_string(value: String) -> UsageStatus:
	return parse_enum(UsageStatus, value, UsageStatus.OK) as UsageStatus

static func quiz_expecting_from_string(value: String) -> QuizExpecting:
	return parse_enum(QuizExpecting, value, QuizExpecting.NOTHING) as QuizExpecting

static func quiz_intent_from_string(value: String) -> QuizIntent:
	return parse_enum(QuizIntent, value, QuizIntent.UNCLEAR) as QuizIntent

static func quiz_line_role_from_string(value: String) -> QuizLineRole:
	return parse_enum(QuizLineRole, value, QuizLineRole.REACTION) as QuizLineRole

static func quiz_verdict_from_string(value: String) -> QuizVerdict:
	return parse_enum(QuizVerdict, value, QuizVerdict.UNANSWERED) as QuizVerdict

## Matches a server string ("multipleChoice", "multiple_choice", "MULTIPLE_CHOICE")
## against an enum's member names, ignoring case and separators. Returns fallback
## for anything it does not recognise, so a new server value never breaks a game.
static func parse_enum(enum_dict: Dictionary, value: String, fallback: int) -> int:
	var wanted := _normalize(value)
	if wanted.is_empty():
		return fallback
	for key in enum_dict.keys():
		if _normalize(str(key)) == wanted:
			return int(enum_dict[key])
	return fallback

static func _normalize(value: String) -> String:
	return value.strip_edges().to_lower().replace("_", "").replace("-", "").replace(" ", "")
