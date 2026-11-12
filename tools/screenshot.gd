extends SceneTree
## Bild-Test-Werkzeug: startet eine Szene, wartet einige Bilder und speichert einen Screenshot.
## Aufruf: godot --resolution 2340x1080 --path . -s tools/screenshot.gd -- <szene> <ausgabe.png> [sprache]
## Ohne Bildschirm (Server, CI): mit xvfb-run und --rendering-method gl_compatibility starten.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("Aufruf: -- <szene> <ausgabe.png> [sprache]")
		quit(2)
		return
	_run(args)


func _run(args: PackedStringArray) -> void:
	var packed: PackedScene = load(args[0])
	if packed == null:
		printerr("Szene nicht gefunden: %s" % args[0])
		quit(1)
		return
	await process_frame
	if args.size() >= 3:
		# Sprache nur für diesen Lauf setzen, ohne die Einstellungsdatei zu ändern.
		var settings := root.get_node_or_null("Settings")
		if settings:
			settings.language = args[2]
		TranslationServer.set_locale(args[2])
	root.add_child(packed.instantiate())
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(args[1])
	print("Screenshot %s: %s" % [args[1], "ok" if err == OK else "Fehler %d" % err])
	quit(0 if err == OK else 1)
