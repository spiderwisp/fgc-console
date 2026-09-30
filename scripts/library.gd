extends Node

signal changed
signal game_started
signal game_finished
const Catalog=preload("res://scripts/catalog.gd")
const Archive=preload("res://scripts/archive.gd")
var games: Array=[]
var installed: Dictionary={}
var connection="Starting library"
var message=""
var busy=false
var progress=0.0
var phase=""
var active_id=""
var platform="windows-x86_64" if OS.get_name()=="Windows" else "linux-x86_64"
var catalog_http: HTTPRequest
var download_http: HTTPRequest
var worker: Thread
var downloading: Dictionary={}
var downloading_build: Dictionary={}
var downloaded_path=""
var game_pid=-1
var session_path=""
var session_deadline=0.0
var launch_time=0.0
var poll_time=0.0

func _ready():
	for folder in ["games","downloads","sessions","artwork"]:DirAccess.make_dir_recursive_absolute(local(folder))
	var initial=read_json("res://catalog/games.json")
	if Catalog.validate(initial).is_empty():games=initial.games
	var cached=read_json("user://catalog.json")
	if Catalog.validate(cached).is_empty():games=cached.games
	var state=read_json("user://installed.json")
	if state is Dictionary:installed=state
	catalog_http=HTTPRequest.new();catalog_http.timeout=15;catalog_http.body_size_limit=2097152;add_child(catalog_http)
	catalog_http.request_completed.connect(catalog_received)
	download_http=HTTPRequest.new();download_http.timeout=600;download_http.body_size_limit=Catalog.MAX_DOWNLOAD;download_http.use_threads=true;add_child(download_http)
	download_http.request_completed.connect(download_received)
	refresh()

func local(path: String) -> String:
	return ProjectSettings.globalize_path("user://"+path)

func read_json(path: String):
	if not FileAccess.file_exists(path):return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func save_json(path: String, data) -> bool:
	var f=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if not f:return false
	f.store_string(JSON.stringify(data,"\t"));f.close()
	return DirAccess.rename_absolute(path+".tmp",path)==OK

func refresh():
	if catalog_http.get_http_client_status()!=HTTPClient.STATUS_DISCONNECTED:return
	connection="Refreshing catalog";changed.emit()
	var url=Catalog.URL+"?refresh="+str(int(Time.get_unix_time_from_system()))
	if catalog_http.request(url,["Cache-Control: no-cache"])!=OK:
		connection="Offline · saved catalog";changed.emit()

func catalog_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200:
		connection="Offline · saved catalog";changed.emit();return
	var data=JSON.parse_string(body.get_string_from_utf8())
	var problem=Catalog.validate(data)
	if not problem.is_empty():
		connection="Saved catalog";message="The catalog update was invalid. Your saved library is still available.";changed.emit();return
	games=data.games;save_json("user://catalog.json",data)
	connection="Catalog up to date";changed.emit()

func build_for(game: Dictionary) -> Dictionary:
	return game.platforms.get(platform,{})

func install_info(id: String) -> Dictionary:
	var info=installed.get(id,{})
	if not info is Dictionary:return {}
	if not Catalog.matches(info.get("sha256"),"^[a-f0-9]{64}$") or not Catalog.safe_path(info.get("executable")):return {}
	if not FileAccess.file_exists(install_dir(id,info.sha256).path_join(info.executable)):return {}
	return info

func install_dir(id: String, digest: String) -> String:
	return local("games/"+id+"/"+digest)

func install_game(game: Dictionary):
	if busy or game_pid>0:return
	var build=build_for(game)
	if build.is_empty():return
	busy=true;phase="Downloading "+game.title;progress=0;message=""
	downloading=game.duplicate(true);downloading_build=build.duplicate(true)
	downloaded_path=local("downloads/"+game.id+".zip.part")
	download_http.download_file=downloaded_path
	changed.emit()
	var err=download_http.request(Catalog.download_url(game,build))
	if err!=OK:finish_install("Could not start the download. Check your connection.","")

func download_received(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray):
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200:
		finish_install("Download failed. Your existing installation is unchanged.","");return
	var f=FileAccess.open(downloaded_path,FileAccess.READ)
	if not f or f.get_length()!=int(downloading_build.size):
		finish_install("The download size did not match the approved package.","");return
	f.close();phase="Verifying and installing "+downloading.title;progress=1;changed.emit()
	worker=Thread.new()
	var staging=local("games/.staging-"+downloading.id+"-"+str(Time.get_ticks_usec()))
	if worker.start(extract_package.bind(downloaded_path,staging,downloading_build.duplicate(true)))!=OK:
		worker=null;finish_install("Could not start the installer.","")

func extract_package(path: String, staging: String, build: Dictionary):
	var problem=Archive.extract(path,staging,build)
	finish_install.call_deferred(problem,staging)

func finish_install(problem: String, staging: String):
	if worker:
		worker.wait_to_finish();worker=null
	var error=problem
	if error.is_empty():
		var target=install_dir(downloading.id,downloading_build.sha256)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if DirAccess.dir_exists_absolute(target):Archive.remove_tree(target,local("games"))
		if DirAccess.rename_absolute(staging,target)!=OK:error="Could not finish the installation."
		else:
			var previous=installed.duplicate(true)
			installed[downloading.id]=downloading_build.duplicate(true)
			installed[downloading.id]["version"]=downloading.version
			if not save_json("user://installed.json",installed):
				installed=previous;error="Could not save the installation record."
	if not staging.is_empty() and DirAccess.dir_exists_absolute(staging):Archive.remove_tree(staging,local("games"))
	if not downloaded_path.is_empty():DirAccess.remove_absolute(downloaded_path)
	message=downloading.get("title","Game")+" is ready to play." if error.is_empty() else error
	busy=false;phase="";progress=0;changed.emit()

func launch(game: Dictionary):
	if game_pid>0:return
	var info=install_info(game.id)
	if info.is_empty():return
	var executable=install_dir(game.id,info.sha256).path_join(info.executable)
	var args=PackedStringArray()
	for arg in info.get("args",[]):
		if arg is String:args.append(arg)
	session_path="";session_deadline=0.0
	if info.get("session_protocol","")=="fgc-v1":
		session_path=local("sessions/"+game.id+"-"+str(Time.get_ticks_usec())+".json")
		args.append_array(["--","--fgc-session="+session_path])
	if OS.get_name()=="Linux":
		var env_args=PackedStringArray(["--chdir="+executable.get_base_dir(),executable]);env_args.append_array(args)
		game_pid=OS.create_process("/usr/bin/env",env_args)
	else:game_pid=OS.create_process(executable,args)
	if game_pid<0:message="The game could not start.";changed.emit();return
	active_id=game.id;launch_time=Time.get_unix_time_from_system();game_started.emit();changed.emit()

func _process(dt):
	if busy and not worker:
		progress=clampf(float(download_http.get_downloaded_bytes())/maxf(float(downloading_build.get("size",1)),1),0,1)
	poll_time+=dt
	if poll_time<.5 or game_pid<0:return
	poll_time=0
	var now=Time.get_unix_time_from_system()
	if not session_path.is_empty():
		var session=read_json(session_path)
		if session is Dictionary:
			var heartbeat=float(session.get("time",0))
			if heartbeat>=now-45 and heartbeat<=now+2:
				if session.get("state") in ["running","restarting"]:session_deadline=heartbeat+45
				if session.get("state")=="running":game_pid=int(session.get("pid",game_pid))
				if session.get("state")=="exited":session_deadline=0.0
		if now<session_deadline:return
	if OS.is_process_running(game_pid):return
	if now-launch_time<4:return
	game_pid=-1;active_id=""
	if not session_path.is_empty():DirAccess.remove_absolute(session_path);session_path=""
	message="Welcome back to FGC.";game_finished.emit();changed.emit()

func _exit_tree():
	if worker:worker.wait_to_finish()
