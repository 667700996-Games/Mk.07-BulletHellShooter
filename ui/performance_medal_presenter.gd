class_name PerformanceMedalPresenter
extends RefCounted

## Read-only presentation adapter for ScoreManager's medal contract.
##
## Screens consume these rows instead of duplicating medal names, conditions,
## or bonus values. Consequently an authored scoring change is reflected in
## every medal UI on the next build.


static func briefing_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for definition in ScoreManager.medal_definitions():
		var medal_id := String(definition.get("id", ""))
		var title_key := String(definition.get("title_key", ""))
		var description_key := String(definition.get("description_key", ""))
		var bonus := maxi(0, int(definition.get("bonus", 0)))
		if medal_id.is_empty() or title_key.is_empty() or description_key.is_empty() or bonus <= 0:
			continue
		rows.append({
			"id": medal_id,
			"title_key": title_key,
			"description_key": description_key,
			"title": GameText.text(title_key),
			"description": GameText.text(description_key),
			"bonus": bonus,
			"bonus_text": "+%06d" % bonus
		})
	return rows
