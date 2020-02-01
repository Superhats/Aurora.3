// The area list is put together here, because some things need it early on. Turrets controls, for example.

/datum/controller/subsystem/finalize
	name = "Map Finalization"
	flags = SS_NO_FIRE | SS_NO_DISPLAY
	init_order = SS_INIT_MAPFINALIZE

	var/dmm_suite/maploader
	var/datum/space_ruin/selected_ruin

/datum/controller/subsystem/finalize/Initialize(timeofday)
	// Setup the global antag uplink. This needs to be done after SSatlas as it requires current_map.
	global.uplink = new

	var/time = world.time
	current_map.finalize_load()
	log_ss("finalize", "Finalized map in [(world.time - time)/10] seconds.")

	select_ruin()
	load_space_ruin()

	if(config.dungeon_chance > 0)
		place_dungeon_spawns()

	if(config.generate_asteroid)
		time = world.time
		current_map.generate_asteroid()
		log_ss("finalize", "Generated asteroid in [(world.time - time)/10] seconds.")

	// Generate the area list.
	resort_all_areas()

	// This is dependant on markers.
	populate_antag_spawns()

	// Generate contact report.
	generate_contact_report()

	..()

/proc/resort_all_areas()
	all_areas = list()
	for (var/area/A in world)
		all_areas += A

	sortTim(all_areas, /proc/cmp_name_asc)

/datum/controller/subsystem/finalize/proc/select_ruin()
	var/list/ruinconfig = list()
	var/list/ruinlist = list()
	var/list/weightedlist = list()
	log_debug("SSfinalize: Starting Ruin Selection")
	try
		ruinconfig = json_decode(return_file_text("config/space_ruins.json"))
	catch(var/exception/ej)
		log_debug("SSfinalize: Warning: Could not load space ruin config - [ej]")
		return

	for(var/ruinname in ruinconfig)
		log_debug("SSfinalize: Loading ruin: [ruinname]")
		//Create the datums
		var/datum/space_ruin/sr = new(ruinname,ruinconfig[ruinname]["file_name"])
		if("weight" in ruinconfig[ruinname])
			sr.weight = ruinconfig[ruinname]["weight"]
		if("valid_maps" in ruinconfig[ruinname])
			sr.valid_maps = ruinconfig[ruinname]["valid_maps"]
		if("characteristics" in ruinconfig[ruinname])
			sr.characteristics = ruinconfig[ruinname]["characteristics"]

		//Check if the file exists
		if(!fexists("[sr.file_name]"))
			admin_notice("<span class='danger'>Map file [sr.file_name] for ruin [sr.name] does not exist.</span>")
			log_ss("finalize","Map file [sr.file_name] for ruin [sr.name] does not exist.")
			log_debug("SSfinalize: File list in /: [json_encode(flist("/"))]")
			log_debug("SSfinalize: File list in : [json_encode(flist(""))]")
			log_debug("SSfinalize: File list in dynamic_maps/: [json_encode(flist("dynamic_maps/"))]")
			continue
		log_debug("SSfinalize: Map file [sr.file_name] for ruin [sr.name] is present")

		//Build the lists
		if(length(sr.valid_maps))
			if(!(current_map.name in sr.valid_maps))
				log_debug("SSfinalize: [current_map.name] is not a valid map for [sr.name]")
				continue
		ruinlist[sr.name] = sr
		weightedlist[sr.name] = sr.weight

	if(!length(ruinlist))
		log_ss("finalize","Found no valid ruins for current map.")
		return

	log_ss("finalize", "Loaded ruin config.")
	var/ruinname = pickweight(weightedlist)
	selected_ruin = ruinlist[ruinname]
	log_debug("SSfinalize: Selected ruin: [selected_ruin.name]")
	return

/datum/controller/subsystem/finalize/proc/load_space_ruin()
	if(!selected_ruin)
		return

	maploader = new

	var/mfile = "[selected_ruin.file_name]"
	var/time = world.time

	log_debug("Attempting to load ruin [selected_ruin.name] with file: [mfile]")

	if (!maploader.load_map(file(mfile), 0, 0, no_changeturf = TRUE))
		log_ss("finalize", "Failed to load '[mfile]'!")
	else
		log_ss("finalize", "Loaded space ruin on z [world.maxz] in [(world.time - time)/10] seconds.")
		current_map.restricted_levels.Add(world.maxz)
	QDEL_NULL(maploader)

/datum/controller/subsystem/finalize/proc/place_dungeon_spawns()
	var/map_directory = "maps/dungeon_spawns/"
	var/list/files = flist(map_directory)
	var/start_time = world.time
	var/dungeons_placed = 0
	var/dmm_suite/maploader = new

	var/dungeon_chance = config.dungeon_chance

	log_ss("finalize","Attempting to create asteroid dungeons for [length(asteroid_spawn)] different areas, with [length(files) - 1] possible dungeons, with a [dungeon_chance]% chance to spawn a dungeon per area.")

	for(var/turf/spawn_location in asteroid_spawn)

		if(length(files) <= 0) //Sanity
			log_ss("finalize","There aren't enough dungeon map files to fill the entire dungeon map. There may be less dungeons than expected.")
			break

		if(prob(dungeon_chance))

			var/chosen_dungeon = pick(files)

			if(!dd_hassuffix(chosen_dungeon,".dmm")) //Don't read anything that isn't a map file
				files -= chosen_dungeon
				log_ss("finalize","ALERT: [chosen_dungeon] is not a .dmm file! Skipping!")
				continue

			var/map_file = file("[map_directory][chosen_dungeon]")

			if(isfile(map_file)) //Sanity
				log_ss("finalize","Loading dungeon '[chosen_dungeon]' at coordinates [spawn_location.x], [spawn_location.y], [spawn_location.z].")
				maploader.load_map(map_file,spawn_location.x,spawn_location.y,spawn_location.z)
				dungeons_placed += 1
			else
				log_ss("finalize","ERROR: Something weird happened with the file: [chosen_dungeon].")

			if(dd_hassuffix(chosen_dungeon,"_unique.dmm")) //Unique dungeons should only spawn once.
				files -= chosen_dungeon

	log_ss("finalize","Loaded [dungeons_placed] asteroid dungeons in [(world.time - start_time)/10] seconds.")

	qdel(maploader)

/datum/controller/subsystem/finalize/proc/generate_contact_report()
	if(!selected_ruin)
		return
	var/report_text = selected_ruin.get_contact_report()
	for(var/obj/effect/landmark/C in landmarks_list)
		if(C.name == "Space Ruin Paper")
			var/obj/item/paper/P = new /obj/item/paper(get_turf(C))
			P.name = "Icarus reading report"
			P.info = report_text
			P.update_icon()
