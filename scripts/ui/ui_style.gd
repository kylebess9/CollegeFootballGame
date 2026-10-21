class_name UiStyle
extends RefCounted
## Shared colors and small helpers so every screen looks consistent.

const BG := Color("#11151c")
const PANEL := Color("#1a202a")
const PANEL_LIGHT := Color("#232b38")
const BORDER := Color("#2e3848")
const TEXT := Color("#e6eaf0")
const MUTED := Color("#8a96a8")
const ACCENT := Color("#f2b134")
const GOOD := Color("#5fd38a")
const BAD := Color("#ff6b6b")


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", BG)
	t.set_color("font_disabled_color", "Button", MUTED)
	t.set_stylebox("normal", "Button", box(PANEL_LIGHT, BORDER, 6))
	t.set_stylebox("hover", "Button", box(Color("#2f3a4b"), ACCENT, 6))
	t.set_stylebox("pressed", "Button", box(ACCENT, ACCENT, 6))
	t.set_stylebox("disabled", "Button", box(PANEL, BORDER, 6))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", box(PANEL, BORDER, 8))
	t.set_stylebox("panel", "Panel", box(PANEL, BORDER, 8))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("normal", "RichTextLabel", box(Color("#151a22"), BORDER, 6))
	t.set_stylebox("panel", "Tree", box(Color("#151a22"), BORDER, 6))
	t.set_color("font_color", "Tree", TEXT)
	t.set_color("title_button_color", "Tree", ACCENT)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_stylebox("normal", "OptionButton", box(PANEL_LIGHT, BORDER, 6))
	t.set_stylebox("hover", "OptionButton", box(Color("#2f3a4b"), ACCENT, 6))
	t.set_stylebox("panel", "TooltipPanel", box(Color("#0d1117"), ACCENT, 6))
	t.set_color("font_color", "TooltipLabel", TEXT)
	return t


static func box(bg: Color, border: Color, radius: int, pad: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad + 2
	s.content_margin_right = pad + 2
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s


static func label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(0, 38)
	return b


static func color_chip(c: Color, size: float = 18.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.custom_minimum_size = Vector2(size, size)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


static func margin(child: Control, px: int) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, px)
	m.add_child(child)
	return m
