class_name ThemeUtils extends RefCounted

# These will be initialized in the _init_fonts() static function
static var regular_font: Font
static var bold_font: Font
static var mono_font: Font

# Initialize fonts
static func _init_fonts() -> void:
	if regular_font == null:
		regular_font = load("res://theme/assets/fonts/Font.ttf")
		bold_font = load("res://theme/assets/fonts/FontBold.ttf")
		mono_font = load("res://theme/assets/fonts/FontMono.ttf")

# Panel colors
const common_panel_inner_color = Color("191926")
const common_panel_border_color = Color("414159")
const dark_panel_color = Color("11111a")
const overlay_panel_inner_color = Color("060614")
const overlay_panel_border_color = Color("344166")

# Text colors
const common_text_color = Color("ffffffdd")
const common_highlighted_text_color = Color("ffffff")
const common_dim_text_color = Color("ffffffbb")
const common_subtle_text_color = Color("ffffff55")

# Button colors
const common_button_inner_color_normal = Color("1c1e38")
const common_button_border_color_normal = Color("313859")
const common_button_inner_color_hover = Color("232840")
const common_button_border_color_hover = Color("43567a")
const common_button_inner_color_pressed = Color("3d5499")
const common_button_border_color_pressed = Color("608fbf")

# Icon colors
const icon_normal_color = Color("bfbfbf")
const icon_hover_color = Color("ffffff")
const icon_pressed_color = Color("bfdfff")

# Tab colors
const tab_container_panel_inner_color = Color("171726")
const tab_container_panel_border_color = Color("2a2e4d")
const tabbar_background_color = Color("13131f80")
const hovered_tab_color = Color("1f2138")
const normal_tab_color = Color("17192e")
const selected_tab_color = Color("293052")
const selected_tab_border_color = Color("608fbf")

static func generate_theme() -> Theme:
	# Initialize fonts if not already done
	_init_fonts()
	
	var theme := Theme.new()
	theme.default_font = regular_font
	theme.default_font_size = 13
	_setup_panelcontainer(theme)
	_setup_button(theme)
	_setup_label(theme)
	_setup_tabcontainer(theme)
	return theme

static func generate_and_apply_theme() -> void:
	# Initialize fonts if not already done
	_init_fonts()
	
	var default_theme := ThemeDB.get_default_theme()
	default_theme.default_font = regular_font
	default_theme.default_font_size = 13
	var generated_theme := generate_theme()
	default_theme.merge_with(generated_theme)

static func _setup_panelcontainer(theme: Theme) -> void:
	theme.add_type("PanelContainer")
	var stylebox := StyleBoxFlat.new()
	stylebox.set_corner_radius_all(4)
	stylebox.set_border_width_all(2)
	stylebox.content_margin_left = 2.0
	stylebox.content_margin_right = 2.0
	stylebox.bg_color = common_panel_inner_color
	stylebox.border_color = common_panel_border_color
	theme.set_stylebox("panel", "PanelContainer", stylebox)
	
	theme.add_type("DarkPanel")
	theme.set_type_variation("DarkPanel", "PanelContainer")
	var dark_stylebox := StyleBoxFlat.new()
	dark_stylebox.set_corner_radius_all(3)
	dark_stylebox.content_margin_left = 4.0
	dark_stylebox.content_margin_right = 4.0
	dark_stylebox.content_margin_top = 2.0
	dark_stylebox.content_margin_bottom = 2.0
	dark_stylebox.bg_color = dark_panel_color
	theme.set_stylebox("panel", "DarkPanel", dark_stylebox)

static func _setup_button(theme: Theme) -> void:
	theme.add_type("Button")
	theme.set_constant("h_separation", "Button", 5)
	theme.set_color("font_color", "Button", common_text_color)
	theme.set_color("font_disabled_color", "Button", common_subtle_text_color)
	theme.set_color("font_focus_color", "Button", common_highlighted_text_color)
	theme.set_color("font_hover_color", "Button", common_highlighted_text_color)
	theme.set_color("font_pressed_color", "Button", common_highlighted_text_color)
	
	var button_stylebox := StyleBoxFlat.new()
	button_stylebox.set_corner_radius_all(5)
	button_stylebox.set_border_width_all(2)
	button_stylebox.content_margin_bottom = 3.0
	button_stylebox.content_margin_top = 3.0
	button_stylebox.content_margin_left = 6.0
	button_stylebox.content_margin_right = 6.0
	
	var normal_button_stylebox := button_stylebox.duplicate()
	normal_button_stylebox.bg_color = common_button_inner_color_normal
	normal_button_stylebox.border_color = common_button_border_color_normal
	theme.set_stylebox("normal", "Button", normal_button_stylebox)
	
	var hover_button_stylebox := button_stylebox.duplicate()
	hover_button_stylebox.bg_color = common_button_inner_color_hover
	hover_button_stylebox.border_color = common_button_border_color_hover
	theme.set_stylebox("hover", "Button", hover_button_stylebox)
	
	var pressed_button_stylebox := button_stylebox.duplicate()
	pressed_button_stylebox.bg_color = common_button_inner_color_pressed
	pressed_button_stylebox.border_color = common_button_border_color_pressed
	theme.set_stylebox("pressed", "Button", pressed_button_stylebox)
	
	# Icon Button
	theme.add_type("IconButton")
	theme.set_type_variation("IconButton", "Button")
	var icon_button_stylebox := StyleBoxFlat.new()
	icon_button_stylebox.set_corner_radius_all(5)
	icon_button_stylebox.set_border_width_all(2)
	icon_button_stylebox.set_content_margin_all(4)
	
	var normal_icon_button_stylebox := icon_button_stylebox.duplicate()
	normal_icon_button_stylebox.bg_color = common_button_inner_color_normal
	normal_icon_button_stylebox.border_color = common_button_border_color_normal
	theme.set_stylebox("normal", "IconButton", normal_icon_button_stylebox)
	
	var hover_icon_button_stylebox := icon_button_stylebox.duplicate()
	hover_icon_button_stylebox.bg_color = common_button_inner_color_hover
	hover_icon_button_stylebox.border_color = common_button_border_color_hover
	theme.set_stylebox("hover", "IconButton", hover_icon_button_stylebox)
	
	var pressed_icon_button_stylebox := icon_button_stylebox.duplicate()
	pressed_icon_button_stylebox.bg_color = common_button_inner_color_pressed
	pressed_icon_button_stylebox.border_color = common_button_border_color_pressed
	theme.set_stylebox("pressed", "IconButton", pressed_icon_button_stylebox)

static func _setup_label(theme: Theme) -> void:
	theme.add_type("Label")
	theme.set_color("font_color", "Label", common_text_color)

static func _setup_tabcontainer(theme: Theme) -> void:
	theme.add_type("TabContainer")
	theme.set_color("font_unselected_color", "TabContainer", common_dim_text_color)
	theme.set_color("font_hovered_color", "TabContainer", common_text_color)
	theme.set_color("font_selected_color", "TabContainer", common_highlighted_text_color)
	theme.set_constant("side_margin", "TabContainer", 0)
	theme.set_font_size("font_size", "TabContainer", 14)
	
	var panel_stylebox := StyleBoxFlat.new()
	panel_stylebox.bg_color = tab_container_panel_inner_color
	panel_stylebox.border_color = tab_container_panel_border_color
	panel_stylebox.border_width_left = 2
	panel_stylebox.border_width_right = 2
	panel_stylebox.border_width_bottom = 2
	panel_stylebox.corner_radius_bottom_right = 5
	panel_stylebox.corner_radius_bottom_left = 5
	panel_stylebox.content_margin_left = 8
	panel_stylebox.content_margin_right = 2
	panel_stylebox.content_margin_bottom = 2
	panel_stylebox.content_margin_top = 0
	theme.set_stylebox("panel", "TabContainer", panel_stylebox)
	
	var tab_hover_stylebox := StyleBoxFlat.new()
	tab_hover_stylebox.bg_color = hovered_tab_color
	tab_hover_stylebox.corner_radius_top_left = 4
	tab_hover_stylebox.corner_radius_top_right = 4
	tab_hover_stylebox.content_margin_left = 12
	tab_hover_stylebox.content_margin_right = 12
	tab_hover_stylebox.content_margin_bottom = 3
	tab_hover_stylebox.content_margin_top = 3
	theme.set_stylebox("tab_hovered", "TabContainer", tab_hover_stylebox)
	
	var tab_selected_stylebox := StyleBoxFlat.new()
	tab_selected_stylebox.bg_color = selected_tab_color
	tab_selected_stylebox.border_color = selected_tab_border_color
	tab_selected_stylebox.border_width_top = 2
	tab_selected_stylebox.content_margin_left = 12
	tab_selected_stylebox.content_margin_right = 12
	tab_selected_stylebox.content_margin_bottom = 3
	tab_selected_stylebox.content_margin_top = 3
	theme.set_stylebox("tab_selected", "TabContainer", tab_selected_stylebox)
	
	var tab_unselected_stylebox := StyleBoxFlat.new()
	tab_unselected_stylebox.bg_color = normal_tab_color
	tab_unselected_stylebox.corner_radius_top_left = 4
	tab_unselected_stylebox.corner_radius_top_right = 4
	tab_unselected_stylebox.content_margin_left = 12
	tab_unselected_stylebox.content_margin_right = 12
	tab_unselected_stylebox.content_margin_bottom = 3
	tab_unselected_stylebox.content_margin_top = 3
	theme.set_stylebox("tab_unselected", "TabContainer", tab_unselected_stylebox)
	
	var tabbar_background_stylebox := StyleBoxFlat.new()
	tabbar_background_stylebox.bg_color = tabbar_background_color
	tabbar_background_stylebox.set_content_margin_all(0)
	tabbar_background_stylebox.corner_radius_top_left = 5
	tabbar_background_stylebox.corner_radius_top_right = 5
	theme.set_stylebox("tabbar_background", "TabContainer", tabbar_background_stylebox)

static func _icon(name: String) -> Texture2D:
	return load("res://theme/assets/icons/theme/" + name + ".svg")