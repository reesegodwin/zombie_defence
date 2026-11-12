# A place on the scavenging map. Each is a .tres file in data/sites/ that you
# can tune in the Inspector. The file name (without .tres) is the site's key.
@tool
class_name ScavengeSite
extends Resource

enum Scrap { LOW, MEDIUM, HIGH }

@export var display_name := "Gas station"
@export_multiline var note := ""          ## Scribbled on the map under the name.
@export var map_position := Vector2(0.5, 0.7)   ## 0..1 across and down the map.
@export_enum("house", "shop", "farm", "tower", "trailer", "police", "rail") var icon := "house"
@export_group("Trip")
@export var gone_seconds := 60.0          ## Total time away, walking there and back included.
@export var scrap := Scrap.LOW
@export_group("Lucky finds")
@export_range(0, 1) var weapon_chance := 0.06
@export_range(0, 1) var food_chance := 0.2
@export_range(0, 1) var survivor_chance := 0.05
@export_range(0, 1) var throwable_chance := 0.3   ## Molotovs or pipe bombs.


func to_dict() -> Dictionary:
	return {
		"name": display_name, "note": note, "pos": map_position, "icon": icon, "gone": gone_seconds,
		"scrap": scrap, "weapon_chance": weapon_chance, "food_chance": food_chance,
		"survivor_chance": survivor_chance, "throw_chance": throwable_chance,
	}
