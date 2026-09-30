extends Node

signal received(action: String, result: Dictionary)
var worker: Thread
var pending_action=""
var last_status: Dictionary={}
var available=false
var poll=0.0
var queue: Array=[]

func _ready():
	available=OS.get_name()=="Linux" and FileAccess.file_exists("/usr/lib/fgc/fgcctl")
	if available:request("status")

func request(action: String, args: Dictionary={}) -> bool:
	if not available:return false
	if worker:
		if action=="status":return false
		queue.append([action,args.duplicate(true)]);return true
	pending_action=action
	var path=ProjectSettings.globalize_path("user://system-"+str(Time.get_ticks_usec())+".json")
	var file=FileAccess.open(path,FileAccess.WRITE)
	if not file:received.emit(action,{"ok":false,"error":"Could not prepare the console request."});return false
	file.store_string(JSON.stringify({"action":action,"args":args}));file.close()
	FileAccess.set_unix_permissions(path,FileAccess.UNIX_READ_OWNER|FileAccess.UNIX_WRITE_OWNER)
	worker=Thread.new()
	if worker.start(execute.bind(path))!=OK:worker=null;DirAccess.remove_absolute(path);return false
	return true

func execute(path: String) -> Dictionary:
	var output=[]
	OS.execute("/usr/lib/fgc/fgcctl",[path],output,true)
	DirAccess.remove_absolute(path)
	var parsed=JSON.parse_string("".join(output))
	return parsed if parsed is Dictionary else {"ok":false,"error":"The console service did not respond."}

func _process(delta):
	if worker and not worker.is_alive():
		var result=worker.wait_to_finish();worker=null
		var action=pending_action
		if action=="status" and result.get("ok"):last_status=result
		received.emit(action,result)
	if not worker and not queue.is_empty():
		var next=queue.pop_front();request(next[0],next[1])
	poll+=delta
	if available and poll>2.0 and not worker:
		poll=0;request("status")

func _exit_tree():
	if worker:worker.wait_to_finish()
