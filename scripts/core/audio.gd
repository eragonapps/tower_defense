extends Node
## Geräusche. Als Autoload "Sfx" registriert.
## Spielt kurze Töne über einen kleinen Vorrat an Abspielern und begrenzt,
## wie oft derselbe Ton kurz hintereinander startet.

const DIR := "res://assets/audio/"
## Name im Spiel → Dateien (ohne Endung). Bei mehreren wird abgewechselt.
const SOUNDS := {
	"click": ["kenney_rpg_audio/metalClick"],
	"build": ["kenney_impact_sounds/impactWood_heavy_000", "kenney_impact_sounds/impactPlank_medium_000"],
	"upgrade": ["kenney_impact_sounds/impactMetal_heavy_000", "kenney_rpg_audio/metalLatch"],
	"sell": ["kenney_rpg_audio/handleCoins"],
	"dig": ["kenney_impact_sounds/impactMining_000", "kenney_impact_sounds/impactMining_001"],
	"fill": ["kenney_impact_sounds/impactSoft_heavy_001"],
	# Ein einziger dumpfer Holzton. Der Armbrustschütze schießt am häufigsten, sein Ton muss unauffällig sein.
	"shoot_bolt": ["kenney_impact_sounds/impactWood_light_000"],
	"shoot_stone": ["kenney_rpg_audio/cloth1", "kenney_rpg_audio/chop"],
	"shoot_fire": ["kenney_rpg_audio/cloth3"],
	"rune": ["kenney_impact_sounds/impactBell_heavy_000"],
	"hit": ["kenney_impact_sounds/impactPunch_medium_000"],
	"blast": ["kenney_impact_sounds/impactSoft_heavy_000"],
	"bones": ["kenney_impact_sounds/impactPlate_light_000", "kenney_impact_sounds/impactPlate_light_001", "kenney_impact_sounds/impactTin_medium_000"],
	"leak": ["kenney_impact_sounds/impactPunch_heavy_000"],
	"wave": ["kenney_impact_sounds/impactBell_heavy_002"],
	"victory": ["kenney_rpg_audio/handleCoins2"],
	"defeat": ["kenney_rpg_audio/doorClose_4"],
}
const PLAYERS := 12
## Derselbe Ton startet frühestens nach dieser Zeit erneut (Millisekunden).
const MIN_GAP_MS := 70

var _players: Array[AudioStreamPlayer] = []
var _streams := {}
var _last_played := {}
var _turn := {}
var _next_player := 0
## Zählt die gestarteten Töne. Für Tests.
var played := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in PLAYERS:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for name in SOUNDS:
		var list := []
		for file in SOUNDS[name]:
			var stream: AudioStream = load(DIR + file + ".ogg")
			if stream != null:
				list.append(stream)
		_streams[name] = list


func play(name: String, volume_db := 0.0) -> void:
	if not Settings.sound_enabled or not _streams.has(name) or _streams[name].is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(name, -MIN_GAP_MS)) < MIN_GAP_MS:
		return
	_last_played[name] = now
	played[name] = int(played.get(name, 0)) + 1
	var list: Array = _streams[name]
	_turn[name] = (int(_turn.get(name, -1)) + 1) % list.size()
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % PLAYERS
	p.stream = list[_turn[name]]
	p.volume_db = volume_db
	p.pitch_scale = 0.94 + 0.12 * fmod(now * 0.0137, 1.0)
	p.play()
