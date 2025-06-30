extends Control
class_name CacheProgress
func _ready() -> void:
    # Connect the cache_field signal to the pre_cache_current_field function
    %Label.text = ""

func update(progress: float, current: String) -> void:
    # Update the label with the current progress
    %Label.text = current
    $ProgressBar.value = progress
    
    # If progress is complete, hide the cache progress scene
    if progress >= 100.0:
        hide()
