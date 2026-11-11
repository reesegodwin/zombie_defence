# One upgrade card offered on level-up.
extends Button

const D = preload("res://scripts/defs.gd")

@onready var tag_label: Label = %Tag
@onready var title_label: Label = %Title
@onready var desc_label: Label = %Desc
@onready var stripe: ColorRect = %Stripe


func setup(card: Dictionary, index: int) -> void:
	var col := Color("e0b44a")
	if card["id"] == "item":
		col = D.KIND_COLORS[D.item_kind(card["key"])]
	elif card["id"] == "hire" or card["id"] == "drill":
		col = Color("c9c9c9")
	tag_label.text = "%d  ·  %s" % [index + 1, String(card["tag"]).to_upper()]
	tag_label.add_theme_color_override("font_color", col)
	stripe.color = col
	title_label.text = card["title"]
	desc_label.text = card["desc"]
