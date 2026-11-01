class_name NeocortexApiAccount
extends RefCounted

## Developer account info from GET /v3/account. Read-only and unmetered.

var tier: String
## The team owner's email, masked by the server for non-editor keys (a*****@example.com).
var email: String
var credits_remaining: int = 0
## ISO-8601 string as returned by the server; empty when not provided.
var next_refresh: String

static func from_dict(data: Dictionary) -> NeocortexApiAccount:
	var account := NeocortexApiAccount.new()
	account.tier = str(data.get("tier", ""))
	account.email = str(data.get("email", ""))
	account.credits_remaining = int(data.get("creditsRemaining", 0))
	account.next_refresh = str(data.get("nextRefresh", ""))
	return account
