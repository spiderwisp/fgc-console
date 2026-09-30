extends RefCounted

const URL="https://raw.githubusercontent.com/spiderwisp/fgc-console/main/catalog/games.json"
const ART_URL="https://raw.githubusercontent.com/spiderwisp/fgc-console/main/"
const MAX_DOWNLOAD=536870912

static func matches(value, pattern: String) -> bool:
	if not value is String:return false
	var re=RegEx.new();re.compile(pattern)
	return re.search(value)!=null

static func safe_path(value) -> bool:
	if not value is String or value.is_empty() or value.length()>240:return false
	if value.begins_with("/") or "\\" in value or ":" in value:return false
	for char in ["*","?","\"","<",">","|"]:
		if char in value:return false
	if not matches(value,"^[ -~]+$"):return false
	for part in value.trim_suffix("/").split("/"):
		if part in ["",".",".."] or part.ends_with(".") or part.ends_with(" "):return false
		if part.get_slice(".",0).to_upper() in ["CON","PRN","AUX","NUL","COM1","COM2","COM3","COM4","LPT1","LPT2","LPT3"]:return false
	return true

static func validate(data) -> String:
	if not data is Dictionary or data.get("schema_version")!=1:return "Unsupported catalog format."
	var games=data.get("games")
	if not games is Array or games.size()>500:return "Invalid catalog size."
	var ids={};var repositories={}
	for game in games:
		if not game is Dictionary:return "Invalid game entry."
		if not matches(game.get("id"),"^[a-z0-9][a-z0-9-]{1,63}$"):return "Invalid game ID."
		if ids.has(game.id):return "Duplicate game ID."
		ids[game.id]=true
		if not matches(game.get("repo"),"^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}$"):return "Invalid GitHub repository."
		if repositories.has(game.repo.to_lower()):return "Duplicate GitHub repository."
		repositories[game.repo.to_lower()]=true
		for field in ["title","description","license","version"]:
			if not game.get(field) is String or game[field].is_empty() or game[field].length()>(500 if field=="description" else 80):return "Missing game details."
		if not matches(game.get("release"),"^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$"):return "Invalid release tag."
		if game.get("gamepad")!=true:return "Controller support is required."
		if not game.get("tags") is Array or game.tags.size()>8:return "Invalid tags."
		for tag in game.tags:
			if not tag is String or tag.length()>24:return "Invalid tag."
		if game.get("cover","")!="catalog/artwork/"+game.id+".jpg":return "Invalid cover path."
		if not game.get("platforms") is Dictionary or not game.platforms.has("linux-x86_64"):return "A Linux build is required."
		for platform in game.platforms:
			if platform not in ["linux-x86_64","windows-x86_64"]:return "Unknown platform."
			var build=game.platforms[platform]
			if not build is Dictionary:return "Invalid build."
			if not matches(build.get("asset"),"^[A-Za-z0-9][A-Za-z0-9_.-]{0,119}\\.zip$"):return "Invalid release asset."
			if not matches(build.get("sha256"),"^[a-f0-9]{64}$"):return "Missing download checksum."
			if not build.get("size") is float and not build.get("size") is int:return "Missing download size."
			if build.size<1 or build.size>MAX_DOWNLOAD:return "Download is too large."
			if not safe_path(build.get("executable")) or build.executable.ends_with("/"):return "Invalid executable path."
			if not build.get("args",[]) is Array or build.get("args",[]).size()>16:return "Invalid launch arguments."
			for arg in build.get("args",[]):
				if not arg is String or arg.length()>256 or "\n" in arg or "\r" in arg:return "Invalid launch argument."
			if build.get("session_protocol","") not in ["","fgc-v1"]:return "Unknown session protocol."
	return ""

static func download_url(game: Dictionary, build: Dictionary) -> String:
	return "https://github.com/"+game.repo+"/releases/download/"+game.release+"/"+build.asset
