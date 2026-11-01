class_name NeocortexArabicFixer
extends RefCounted

## GDScript port of Abdullah Konash's ArabicSupport plugin (MIT). It flips Arabic text
## and swaps letters to their correct contextual (isolated / initial / medial / final)
## presentation forms.
##
## NOTE: Godot's TextServer already shapes Arabic from base characters, so this is
## opt-in (see NeocortexText.correct_rtl). Use it only when rendering with a pipeline
## that does not shape Arabic, or when you need these exact presentation forms.

# ------------------------------------------------------------------
# ISOLATED PRESENTATION FORMS referenced by the shaping rules
# ------------------------------------------------------------------

const _HAMZA := 0xFE80
const _ALEF := 0xFE8D
const _ALEF_HAMZA := 0xFE83
const _WAW_HAMZA := 0xFE85
const _ALEF_MAKSOOR := 0xFE87
const _ALEF_MAD := 0xFE81
const _DAL := 0xFEA9
const _THAL := 0xFEAB
const _RA2 := 0xFEAD
const _ZEEN := 0xFEAF
const _PERSIAN_ZE := 0xFB8A
const _WAW := 0xFEED
const _LAM := 0xFEDD

# Lam-Alef ligatures
const _LAM_ALEF_MAKSOOR := 0xFEF7
const _LAM_ALEF := 0xFEF9
const _LAM_ALEF_HAMZA := 0xFEF5
const _LAM_ALEF_MAD := 0xFEF3

const _REMOVED := 0xFFFF

# General (base) Arabic letter -> isolated presentation form.
const _MAP := {
	0x0621: 0xFE80, # Hamza
	0x0627: 0xFE8D, # Alef
	0x0623: 0xFE83, # AlefHamza
	0x0624: 0xFE85, # WawHamza
	0x0625: 0xFE87, # AlefMaksoor
	0x0649: 0xFBFC, # AlefMagsora -> AlefMaksora
	0x0626: 0xFE89, # HamzaNabera
	0x0628: 0xFE8F, # Ba
	0x062A: 0xFE95, # Ta
	0x062B: 0xFE99, # Tha2
	0x062C: 0xFE9D, # Jeem
	0x062D: 0xFEA1, # H7aa
	0x062E: 0xFEA5, # Khaa2
	0x062F: 0xFEA9, # Dal
	0x0630: 0xFEAB, # Thal
	0x0631: 0xFEAD, # Ra2
	0x0632: 0xFEAF, # Zeen
	0x0633: 0xFEB1, # Seen
	0x0634: 0xFEB5, # Sheen
	0x0635: 0xFEB9, # S9a
	0x0636: 0xFEBD, # Dha
	0x0637: 0xFEC1, # T6a
	0x0638: 0xFEC5, # T6ha
	0x0639: 0xFEC9, # Ain
	0x063A: 0xFECD, # Gain
	0x0641: 0xFED1, # Fa
	0x0642: 0xFED5, # Gaf
	0x0643: 0xFED9, # Kaf
	0x0644: 0xFEDD, # Lam
	0x0645: 0xFEE1, # Meem
	0x0646: 0xFEE5, # Noon
	0x0647: 0xFEE9, # Ha
	0x0648: 0xFEED, # Waw
	0x064A: 0xFEF1, # Ya
	0x0622: 0xFE81, # AlefMad
	0x0629: 0xFE93, # TaMarboota
	0x067E: 0xFB56, # PersianPe
	0x0686: 0xFB7A, # PersianChe
	0x0698: 0xFB8A, # PersianZe
	0x06AF: 0xFB92, # PersianGaf
	0x06A9: 0xFB8E, # PersianGaf2
	0x06CC: 0xFBFC, # PersianYeh
}

const _ASCII_PUNCTUATION := "!\"#%&'()*,-./:;?@[\\]_{}"
const _ASCII_SYMBOL := "$+<=>^`|~"

# ------------------------------------------------------------------
# PUBLIC API
# ------------------------------------------------------------------

## Fixes a string for RTL display.
static func fix(text: String, show_tashkeel: bool = false, combine_tashkeel: bool = true, use_hindu_numbers: bool = true) -> String:
	if text.is_empty():
		return text

	var normalized := text.replace("\n", "\n")
	if not normalized.contains("\n"):
		return _fix_line(normalized, show_tashkeel, combine_tashkeel, use_hindu_numbers)

	var lines := normalized.split("\n", true)
	var out: PackedStringArray = []
	for line in lines:
		out.append(_fix_line(line, show_tashkeel, combine_tashkeel, use_hindu_numbers))
	return "\n".join(out)

# ------------------------------------------------------------------
# CORE
# ------------------------------------------------------------------

static func _fix_line(text: String, show_tashkeel: bool, combine_tashkeel: bool, use_hindu_numbers: bool) -> String:
	var tashkeel: Array = []
	var stripped := _remove_tashkeel(text, combine_tashkeel, tashkeel)

	var letters_origin: Array = []
	var letters_final: Array = []
	for i in stripped.length():
		var code := stripped.unicode_at(i)
		letters_final.append(code)
		letters_origin.append(_MAP.get(code, code))

	var i := 0
	while i < letters_origin.size():
		var skip := false

		# Special Lam-Alef ligatures.
		if letters_origin[i] == _LAM and i < letters_origin.size() - 1:
			var next: int = letters_origin[i + 1]
			if next == _ALEF_MAKSOOR:
				letters_origin[i] = _LAM_ALEF_MAKSOOR
				letters_final[i + 1] = _REMOVED
				skip = true
			elif next == _ALEF:
				letters_origin[i] = _LAM_ALEF
				letters_final[i + 1] = _REMOVED
				skip = true
			elif next == _ALEF_HAMZA:
				letters_origin[i] = _LAM_ALEF_HAMZA
				letters_final[i + 1] = _REMOVED
				skip = true
			elif next == _ALEF_MAD:
				letters_origin[i] = _LAM_ALEF_MAD
				letters_final[i + 1] = _REMOVED
				skip = true

		if not _is_ignored_character(letters_origin[i]):
			if _is_middle_letter(letters_origin, i):
				letters_final[i] = letters_origin[i] + 3
			elif _is_finishing_letter(letters_origin, i):
				letters_final[i] = letters_origin[i] + 1
			elif _is_leading_letter(letters_origin, i):
				letters_final[i] = letters_origin[i] + 2

		if skip:
			i += 1

		if use_hindu_numbers:
			letters_final[i] = _handle_hindu_number(letters_origin[i], letters_final[i])

		i += 1

	if show_tashkeel and tashkeel.size() > 0:
		letters_final = _return_tashkeel(letters_final, tashkeel)

	return _reverse_and_build(letters_final)

# Builds the visual (reversed) string, keeping runs of Latin/number/symbol text in
# their natural left-to-right order. Mirrors the reverse loop in FixLine.
static func _reverse_and_build(letters: Array) -> String:
	var out: Array = []
	var numbers: Array = []
	var size := letters.size()

	for i in range(size - 1, -1, -1):
		var ch: int = letters[i]

		if _is_punctuation(ch) and i > 0 and i < size - 1 \
				and (_is_punctuation(letters[i - 1]) or _is_punctuation(letters[i + 1])):
			match ch:
				0x28: out.append(0x29) # ( -> )
				0x29: out.append(0x28) # ) -> (
				0x3C: out.append(0x3E) # < -> >
				0x3E: out.append(0x3C) # > -> <
				0x5B: out.append(0x5D) # [ -> ]
				0x5D: out.append(0x5B) # ] -> [
				_:
					if ch != _REMOVED:
						out.append(ch)
		elif ch == 0x20 and i > 0 and i < size - 1 \
				and _is_latin_or_number(letters[i - 1]) and _is_latin_or_number(letters[i + 1]):
			numbers.append(ch)
		elif _is_number(ch) or _is_lower(ch) or _is_upper(ch) or _is_symbol(ch) or _is_punctuation(ch):
			match ch:
				0x28: numbers.append(0x29)
				0x29: numbers.append(0x28)
				0x3C: numbers.append(0x3E)
				0x3E: numbers.append(0x3C)
				0x5B: out.append(0x5D)
				0x5D: out.append(0x5B)
				_: numbers.append(ch)
		elif (ch >= 0xD800 and ch <= 0xDBFF) or (ch >= 0xDC00 and ch <= 0xDFFF):
			numbers.append(ch)
		else:
			_flush_numbers(out, numbers)
			if ch != _REMOVED:
				out.append(ch)

	_flush_numbers(out, numbers)

	var result := ""
	for code in out:
		result += String.chr(code)
	return result

static func _flush_numbers(out: Array, numbers: Array) -> void:
	for j in numbers.size():
		out.append(numbers[numbers.size() - 1 - j])
	numbers.clear()

# ------------------------------------------------------------------
# TASHKEEL
# ------------------------------------------------------------------

# Returns the string with tashkeel removed; appends { "mark": int, "position": int }
# entries to `out_tashkeel`.
static func _remove_tashkeel(text: String, combine_tashkeel: bool, out_tashkeel: Array) -> String:
	var kept: Array = []
	var removed_any := false

	for i in text.length():
		var ch := text.unicode_at(i)
		match ch:
			0x064B, 0x064C, 0x064D, 0x0652, 0x0653: # Tanween / Sukun / Maddah
				out_tashkeel.append({ "mark": ch, "position": i })
				removed_any = true
			0x064E: # Fatha
				if combine_tashkeel and _combine_prev(out_tashkeel, 0x0651, 0xFC60):
					removed_any = true
				else:
					out_tashkeel.append({ "mark": ch, "position": i })
					removed_any = true
			0x064F: # Damma
				if combine_tashkeel and _combine_prev(out_tashkeel, 0x0651, 0xFC61):
					removed_any = true
				else:
					out_tashkeel.append({ "mark": ch, "position": i })
					removed_any = true
			0x0650: # Kasra
				if combine_tashkeel and _combine_prev(out_tashkeel, 0x0651, 0xFC62):
					removed_any = true
				else:
					out_tashkeel.append({ "mark": ch, "position": i })
					removed_any = true
			0x0651: # Shadda
				var combined := false
				if combine_tashkeel:
					combined = _combine_prev(out_tashkeel, 0x064E, 0xFC60) \
						or _combine_prev(out_tashkeel, 0x064F, 0xFC61) \
						or _combine_prev(out_tashkeel, 0x0650, 0xFC62)
				if combined:
					removed_any = true
				else:
					out_tashkeel.append({ "mark": ch, "position": i })
					removed_any = true
			0xFC60, 0xFC61, 0xFC62: # already-combined shadda marks
				removed_any = true
			_:
				kept.append(ch)

	if not removed_any:
		return text

	var result := ""
	for code in kept:
		result += String.chr(code)
	return result

# If the previous tashkeel equals `expected`, replace it with `combined` and report success.
static func _combine_prev(tashkeel: Array, expected: int, combined: int) -> bool:
	if tashkeel.is_empty():
		return false
	var last: Dictionary = tashkeel[tashkeel.size() - 1]
	if last["mark"] == expected:
		last["mark"] = combined
		return true
	return false

static func _return_tashkeel(letters: Array, tashkeel: Array) -> Array:
	var result := letters.duplicate()
	result.resize(letters.size() + tashkeel.size())

	for entry in tashkeel:
		var pos: int = entry["position"]
		for j in range(result.size() - 1, pos, -1):
			result[j] = result[j - 1]
		result[pos] = entry["mark"]

	return result

# ------------------------------------------------------------------
# CHARACTER CLASSIFICATION (approximations of C# char.Is* for ASCII + Arabic)
# ------------------------------------------------------------------

static func _is_number(ch: int) -> bool:
	return (ch >= 0x30 and ch <= 0x39) or (ch >= 0x0660 and ch <= 0x0669)

static func _is_lower(ch: int) -> bool:
	return ch >= 0x61 and ch <= 0x7A

static func _is_upper(ch: int) -> bool:
	return ch >= 0x41 and ch <= 0x5A

static func _is_latin_or_number(ch: int) -> bool:
	return _is_lower(ch) or _is_upper(ch) or _is_number(ch)

static func _is_punctuation(ch: int) -> bool:
	if ch == 0x060C or ch == 0x061B or ch == 0x061F: # Arabic comma/semicolon/question
		return true
	return _ASCII_PUNCTUATION.find(String.chr(ch)) != -1

static func _is_symbol(ch: int) -> bool:
	return _ASCII_SYMBOL.find(String.chr(ch)) != -1

static func _handle_hindu_number(letter_origin: int, letter_final: int) -> int:
	if letter_origin >= 0x0030 and letter_origin <= 0x0039:
		return 0x0660 + (letter_origin - 0x0030)
	return letter_final

static func _is_ignored_character(ch: int) -> bool:
	var is_persian := ch == 0xFB56 or ch == 0xFB7A or ch == 0xFB8A or ch == 0xFB92 or ch == 0xFB8E
	var is_presentation_b := ch <= 0xFEFF and ch >= 0xFE70
	var is_acceptable := is_presentation_b or is_persian or ch == 0xFBFC

	return _is_punctuation(ch) \
		or _is_number(ch) \
		or _is_lower(ch) \
		or _is_upper(ch) \
		or _is_symbol(ch) \
		or not is_acceptable \
		or ch == 0x61 or ch == 0x3E or ch == 0x3C or ch == 0x061B

# ------------------------------------------------------------------
# CONTEXTUAL POSITION CHECKS
# ------------------------------------------------------------------

static func _is_leading_letter(letters: Array, index: int) -> bool:
	var prev: int = letters[index - 1] if index > 0 else 0
	var cannot_be_before_leading := index == 0 \
		or prev == 0x20 or prev == 0x2A or prev == 0x41 \
		or _is_punctuation(prev) or prev == 0x3E or prev == 0x3C \
		or prev == _ALEF or prev == _DAL or prev == _THAL or prev == _RA2 \
		or prev == _ZEEN or prev == _PERSIAN_ZE or prev == _WAW or prev == _ALEF_MAD \
		or prev == _ALEF_HAMZA or prev == _HAMZA or prev == _ALEF_MAKSOOR or prev == _WAW_HAMZA

	var cur: int = letters[index]
	var cannot_be_leading := cur != 0x20 \
		and cur != _DAL and cur != _THAL and cur != _RA2 and cur != _ZEEN \
		and cur != _PERSIAN_ZE and cur != _ALEF and cur != _ALEF_HAMZA \
		and cur != _ALEF_MAKSOOR and cur != _ALEF_MAD and cur != _WAW_HAMZA \
		and cur != _WAW and cur != _HAMZA

	var cannot_be_after_leading := index < letters.size() - 1
	if cannot_be_after_leading:
		var nxt: int = letters[index + 1]
		cannot_be_after_leading = nxt != 0x20 and nxt != 0x0A and nxt != 0x0D \
			and not _is_punctuation(nxt) and not _is_number(nxt) and not _is_symbol(nxt) \
			and not _is_lower(nxt) and not _is_upper(nxt) and nxt != _HAMZA

	return cannot_be_before_leading and cannot_be_leading and cannot_be_after_leading

static func _is_finishing_letter(letters: Array, index: int) -> bool:
	var cannot_be_before_finishing := index != 0
	if cannot_be_before_finishing:
		var prev: int = letters[index - 1]
		cannot_be_before_finishing = prev != 0x20 \
			and prev != _DAL and prev != _THAL and prev != _RA2 and prev != _ZEEN \
			and prev != _PERSIAN_ZE and prev != _WAW and prev != _ALEF and prev != _ALEF_MAD \
			and prev != _ALEF_HAMZA and prev != _ALEF_MAKSOOR and prev != _WAW_HAMZA and prev != _HAMZA \
			and not _is_punctuation(prev) and not _is_symbol(prev) and prev != 0x3E and prev != 0x3C

	var cur: int = letters[index]
	var cannot_be_finishing := cur != 0x20 and cur != _HAMZA

	return cannot_be_before_finishing and cannot_be_finishing

static func _is_middle_letter(letters: Array, index: int) -> bool:
	if index >= letters.size() - 1:
		return false

	var cur: int = letters[index]
	var cannot_be_middle := index != 0 \
		and cur != _ALEF and cur != _DAL and cur != _THAL and cur != _RA2 and cur != _ZEEN \
		and cur != _PERSIAN_ZE and cur != _WAW and cur != _ALEF_MAD and cur != _ALEF_HAMZA \
		and cur != _ALEF_MAKSOOR and cur != _WAW_HAMZA and cur != _HAMZA

	var prev: int = letters[index - 1] if index > 0 else 0
	var cannot_be_before_middle := index != 0 \
		and prev != _ALEF and prev != _DAL and prev != _THAL and prev != _RA2 and prev != _ZEEN \
		and prev != _PERSIAN_ZE and prev != _WAW and prev != _ALEF_MAD and prev != _ALEF_HAMZA \
		and prev != _ALEF_MAKSOOR and prev != _WAW_HAMZA and prev != _HAMZA \
		and not _is_punctuation(prev) and prev != 0x3E and prev != 0x3C and prev != 0x20 and prev != 0x2A

	var nxt: int = letters[index + 1]
	var cannot_be_after_middle := nxt != 0x20 and nxt != 0x0D and nxt != _HAMZA \
		and not _is_number(nxt) and not _is_symbol(nxt) and not _is_punctuation(nxt)

	return cannot_be_after_middle and cannot_be_before_middle and cannot_be_middle and not _is_punctuation(nxt)
