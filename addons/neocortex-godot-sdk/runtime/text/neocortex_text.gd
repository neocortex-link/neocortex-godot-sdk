class_name NeocortexText
extends RefCounted

## String helpers.

## Reshapes Arabic/RTL text into presentation forms (no tashkeel, combined tashkeel,
## Arabic-Indic numerals).
##
## Only needed when the renderer does not shape Arabic itself. Godot's Label shapes
## Arabic natively via TextServer, so prefer that unless you specifically want these
## presentation forms.
static func correct_rtl(text: String) -> String:
	return NeocortexArabicFixer.fix(text)
