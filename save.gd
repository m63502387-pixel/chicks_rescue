extends RefCounted
# Сохранение прогресса: открыт ли второй персонаж (Друн).

const PATH := "user://save.cfg"

static func is_drun_unlocked() -> bool:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return false
	return bool(c.get_value("progress", "drun", false))

static func unlock_drun() -> void:
	var c := ConfigFile.new()
	c.load(PATH)
	c.set_value("progress", "drun", true)
	c.save(PATH)
