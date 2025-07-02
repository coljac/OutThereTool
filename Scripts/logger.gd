extends Node

class_name ColLogger

enum LOG_LEVEL {
    DEBUG,
    INFO,
    WARNING,
    ERROR,
    CRITICAL
}

const LOG_LEVEL_COLOURS = {
    LOG_LEVEL.DEBUG: "green",
    LOG_LEVEL.INFO: "blue",
    LOG_LEVEL.WARNING: "yellow",
    LOG_LEVEL.ERROR: "orange",
    LOG_LEVEL.CRITICAL: "red"
}

@export var log_level: LOG_LEVEL = LOG_LEVEL.INFO
@export var log_to_file: bool = true
@export var log_to_console: bool = true
@export var log_file_path = "/tmp/ot.log"

var file: FileAccess
static var logger: ColLogger

func _ready() -> void:
    if log_to_file:
        file = FileAccess.open(log_file_path, FileAccess.WRITE)
    log_message("Logger initialized", LOG_LEVEL.INFO)
    logger = self


func log_message(message: String, level: LOG_LEVEL = LOG_LEVEL.INFO) -> void:
    if level < log_level:
        return
    var prefix = ""
    match level:
        LOG_LEVEL.DEBUG:
            prefix = "[DEBUG] "
        LOG_LEVEL.INFO:
            prefix = "[INFO] "
        LOG_LEVEL.WARNING:
            prefix = "[WARNING] "
        LOG_LEVEL.ERROR:
            prefix = "[ERROR] "
        LOG_LEVEL.CRITICAL:
            prefix = "[CRITICAL] "
    if log_to_console:
        print_rich("[color=" + LOG_LEVEL_COLOURS[level] + "][b]" + prefix + "[/b][/color]" + message)
    if log_to_file:
        if file:
            file.store_line(prefix + message)
            file.flush()

func info(message: String) -> void:
    log_message(message, LOG_LEVEL.INFO)

func debug(message: String) -> void:
    log_message(message, LOG_LEVEL.DEBUG)

func warning(message: String) -> void:
    log_message(message, LOG_LEVEL.WARNING)

func error(message: String) -> void:
    log_message(message, LOG_LEVEL.ERROR)

func critical(message: String) -> void:
    log_message(message, LOG_LEVEL.CRITICAL)


func _exit_tree() -> void:
    if log_to_file and file:
        file.store_line("Chamdo Logger Shutdown")
        file.close()