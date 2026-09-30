extends RefCounted

const Catalog=preload("res://scripts/catalog.gd")

static func inspect(path: String) -> Dictionary:
	var f=FileAccess.open(path,FileAccess.READ)
	if not f:return {"error":"The download could not be opened."}
	var length=f.get_length()
	if length<22:return {"error":"The download is not a ZIP archive."}
	var tail_start=maxi(0,length-65557);f.seek(tail_start)
	var tail=f.get_buffer(length-tail_start);var end=-1
	for i in range(tail.size()-22,-1,-1):
		if tail.decode_u32(i)==0x06054b50 and i+22+tail.decode_u16(i+20)==tail.size():end=i;break
	if end<0:return {"error":"The ZIP index is missing."}
	if tail.decode_u16(end+4)!=0 or tail.decode_u16(end+6)!=0:return {"error":"Split ZIP archives are unsupported."}
	var count=tail.decode_u16(end+10)
	var cd_size=tail.decode_u32(end+12);var offset=tail.decode_u32(end+16)
	if count<1 or count>4096 or offset+cd_size>tail_start+end:return {"error":"The ZIP index is invalid."}
	f.seek(offset);var entries={};var used={};var total=0
	for i in range(count):
		var h=f.get_buffer(46)
		if h.size()!=46 or h.decode_u32(0)!=0x02014b50:return {"error":"The ZIP index is damaged."}
		var size=h.decode_u32(24);var filename_size=h.decode_u16(28)
		var mode=(h.decode_u32(38)>>16)&0xf000
		if (h.decode_u16(8)&1)!=0 or h.decode_u16(10) not in [0,8]:return {"error":"Encrypted or unsupported ZIP compression."}
		if mode not in [0,0x4000,0x8000]:return {"error":"Links and special files are not allowed in game packages."}
		total+=size
		if size>Catalog.MAX_DOWNLOAD or total>1073741824:return {"error":"The expanded package is too large."}
		var name=f.get_buffer(filename_size).get_string_from_utf8()
		if not Catalog.safe_path(name) or used.has(name.to_lower()):return {"error":"The package contains unsafe or duplicate paths."}
		used[name.to_lower()]=true;entries[name]=size
		f.seek(f.get_position()+h.decode_u16(30)+h.decode_u16(32))
		if f.get_position()>offset+cd_size:return {"error":"The ZIP index is invalid."}
	return {"entries":entries}

static func extract(path: String, target: String, build: Dictionary) -> String:
	if FileAccess.get_sha256(path)!=build.sha256:return "Download checksum did not match. Nothing was installed."
	var index=inspect(path)
	if index.has("error"):return index.error
	if not index.entries.has(build.executable):return "The package does not contain the listed executable."
	var reader=ZIPReader.new()
	if reader.open(path)!=OK:return "The game package could not be read."
	for name in index.entries:
		var destination=target.path_join(name)
		if name.ends_with("/"):
			if DirAccess.make_dir_recursive_absolute(destination)!=OK:return "Could not create the game folder."
			continue
		if DirAccess.make_dir_recursive_absolute(destination.get_base_dir())!=OK:return "Could not create the game folder."
		var bytes=reader.read_file(name)
		if bytes.size()!=index.entries[name]:return "The game package is damaged."
		var file=FileAccess.open(destination,FileAccess.WRITE)
		if not file:return "Could not write the game files. Check available storage."
		file.store_buffer(bytes)
		if file.get_error()!=OK:return "The game files could not be saved."
		file.close()
	reader.close()
	var executable=target.path_join(build.executable)
	var file=FileAccess.open(executable,FileAccess.READ)
	if not file:return "The game executable is missing."
	var magic=file.get_buffer(4);file.close()
	if OS.get_name()=="Windows":
		if magic.size()<2 or magic[0]!=77 or magic[1]!=90:return "The Windows game executable is invalid."
	else:
		if magic!=PackedByteArray([127,69,76,70]):return "The Linux game must be a native ELF executable."
		if OS.execute("/bin/chmod",PackedStringArray(["u+x",executable]))!=0:return "Could not enable the game executable."
	return ""

static func remove_tree(path: String, boundary: String):
	if not path.begins_with(boundary+"/") or not DirAccess.dir_exists_absolute(path):return
	var d=DirAccess.open(path)
	if not d:return
	for name in d.get_files():DirAccess.remove_absolute(path.path_join(name))
	for name in d.get_directories():
		var child=path.path_join(name)
		if d.is_link(name):DirAccess.remove_absolute(child)
		else:remove_tree(child,boundary)
	DirAccess.remove_absolute(path)
