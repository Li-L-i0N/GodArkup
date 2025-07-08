# logger.gd
extends RefCounted
class_name Logger

enum Level { INFO, WARNING, ERROR }

var log_file_path := "res://addons/godarkup/logs/godarkup_latest.log"

# On initialization, clear the log file for the new session.
func _init():
	var file = FileAccess.open(log_file_path, FileAccess.WRITE)
	if file:
		file.close()
	else:
		printerr("[GodArkup.Logger] Failed to clear log file: ", log_file_path)

# Open, write, and close the file for each message to ensure it's saved.
func _log_message(level: Level, message: String):
	var level_str := ""
	match level:
		Level.INFO:
			level_str = "INFO"
		Level.WARNING:
			level_str = "WARNING"
		Level.ERROR:
			level_str = "ERROR"

	var timestamp = Time.get_datetime_string_from_system(false, true)
	var formatted_message = "[%s] [%s] %s" % [timestamp, level_str, message]

	# Open in read-write mode to append to the file.
	var file = FileAccess.open(log_file_path, FileAccess.READ_WRITE)
	if file:
		file.seek_end()
		file.store_line(formatted_message)
		file.close()

	# Also print to the standard Godot output.
	match level:
		Level.WARNING:
			push_warning(message)
		Level.ERROR:
			push_error(message)
		_:
			print(message)

func info(message: String):
	_log_message(Level.INFO, message)

func warning(message: String):
	_log_message(Level.WARNING, message)

func error(message: String):
	_log_message(Level.ERROR, message)
