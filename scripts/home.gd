extends Control

const Library=preload("res://scripts/library.gd")
const Catalog=preload("res://scripts/catalog.gd")
const FONT=preload("res://assets/Rajdhani-Medium.ttf")
const LIME=Color("b2ef77")
const WHITE=Color("edf3f5")
const MUTED=Color("91a4b5")
var library: Node
var content: Control
var selected_id=""
var search=""
var installed_only=false
var popup: PopupPanel
var settings: ConfigFile=ConfigFile.new()
var mapping=-1
var controller_buttons=[0,1]
var map_label: Label
var cover_http: HTTPRequest
var cover_for=""
var covers: Dictionary={}
var cover_view: TextureRect
var primary: Button
var status: Label
var meter: ProgressBar
var ready_ui=false
var fullscreen=false
var appliance_mode=false
var appliance_ui
var system_service

func _ready():
	Engine.max_fps=60
	theme=Theme.new();theme.default_font=FONT;theme.default_font_size=24
	settings.load("user://console.cfg")
	appliance_mode=FileAccess.file_exists("/etc/fgc/os.json") or "--appliance-preview" in OS.get_cmdline_user_args()
	fullscreen=settings.get_value("display","fullscreen",OS.get_name()=="Linux")
	controller_buttons=settings.get_value("input","buttons",[0,1]);bind_controller()
	if DisplayServer.get_name()!="headless" and fullscreen:DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	library=Library.new();library.changed.connect(refresh_view);library.game_started.connect(game_started);library.game_finished.connect(game_finished);add_child(library)
	cover_http=HTTPRequest.new();cover_http.timeout=12;cover_http.body_size_limit=2097152;add_child(cover_http);cover_http.request_completed.connect(cover_received)
	build_header();ready_ui=true;refresh_view()
	if appliance_mode:
		system_service=load("res://scripts/system_bridge.gd").new();add_child(system_service)
		var appliance_layer=CanvasLayer.new();appliance_layer.layer=10;add_child(appliance_layer)
		appliance_ui=load("res://scripts/appliance.gd").new();appliance_layer.add_child(appliance_ui);appliance_ui.setup(self,system_service)

func style(bg: Color, border: Color, width: int=1) -> StyleBoxFlat:
	var s=StyleBoxFlat.new();s.bg_color=bg;s.border_color=border;s.set_border_width_all(width);s.set_corner_radius_all(10);s.content_margin_left=18;s.content_margin_right=18
	return s

func button(parent: Node, title: String, pos: Vector2, size: Vector2, callback: Callable, accent=false) -> Button:
	var b=Button.new();b.text=title;b.position=pos;b.size=size;b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	b.add_theme_color_override("font_color",Color("13211a") if accent else WHITE)
	b.add_theme_color_override("font_focus_color",Color("13211a") if accent else WHITE)
	b.add_theme_color_override("font_hover_color",Color("13211a") if accent else WHITE)
	b.add_theme_stylebox_override("normal",style(LIME if accent else Color("132030"),LIME if accent else Color("26384a")))
	b.add_theme_stylebox_override("hover",style(Color("c9ffa0") if accent else Color("22364a"),LIME))
	b.add_theme_stylebox_override("pressed",style(Color("8aba5b") if accent else Color("263b50"),LIME))
	b.add_theme_stylebox_override("focus",style(Color(0,0,0,0),LIME,2))
	b.add_theme_stylebox_override("disabled",style(Color("1c2931"),Color("293743")))
	b.pressed.connect(callback);parent.add_child(b)
	if is_instance_valid(appliance_ui) and appliance_ui.visible and not appliance_ui.is_ancestor_of(b) and not (is_instance_valid(popup) and popup.is_ancestor_of(b)):
		b.set_meta("home_focus",b.focus_mode);b.focus_mode=Control.FOCUS_NONE
	return b

func suspend_home_focus(suspended: bool):
	for control in find_children("*","Control",true,false):
		if is_instance_valid(appliance_ui) and (control==appliance_ui or appliance_ui.is_ancestor_of(control)):continue
		if is_instance_valid(popup) and popup.is_ancestor_of(control):continue
		if suspended:
			if not control.has_meta("home_focus"):control.set_meta("home_focus",control.focus_mode)
			control.focus_mode=Control.FOCUS_NONE
		elif control.has_meta("home_focus"):
			control.focus_mode=control.get_meta("home_focus");control.remove_meta("home_focus")

func label(parent: Node, text: String, pos: Vector2, size=24, color=WHITE, width=0.0) -> Label:
	var l=Label.new()
	if width>0:l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.text=text;l.position=pos;l.mouse_filter=Control.MOUSE_FILTER_IGNORE;l.add_theme_font_size_override("font_size",size);l.add_theme_color_override("font_color",color)
	if width>0:l.size=Vector2(width,0)
	parent.add_child(l);return l

func build_header():
	label(self,"FGC",Vector2(105,32),39)
	label(self,"FRAMEWORK GAMING CONSOLE",Vector2(108,79),13,MUTED)
	button(self,"All games",Vector2(326,40),Vector2(150,46),func():installed_only=false;refresh_view())
	button(self,"Installed",Vector2(488,40),Vector2(148,46),func():installed_only=true;refresh_view())
	button(self,"Search",Vector2(648,40),Vector2(134,46),show_search)
	button(self,"Settings",Vector2(1086,40),Vector2(146,46),show_settings)
	status=label(self,"",Vector2(48,639),19,LIME,1160)
	meter=ProgressBar.new();meter.position=Vector2(48,667);meter.size=Vector2(1184,4);meter.show_percentage=false;meter.max_value=1;meter.visible=false;add_child(meter)
	meter.add_theme_stylebox_override("background",style(Color("172636"),Color("172636"),0));meter.add_theme_stylebox_override("fill",style(LIME,LIME,0))

func refresh_view():
	if not ready_ui:return
	if content:content.queue_free()
	content=Control.new();add_child(content)
	var filtered=[]
	for game in library.games:
		var searchable=(game.title+" "+game.description+" "+game.repo+" "+" ".join(game.tags)).to_lower()
		if not search.is_empty() and not searchable.contains(search.to_lower()):continue
		if installed_only and library.install_info(game.id).is_empty():continue
		filtered.append(game)
	label(content,"YOUR LIBRARY" if installed_only else "DISCOVER",Vector2(48,119),29)
	label(content,str(filtered.size())+" GAME"+("S" if filtered.size()!=1 else "")+("  /  "+search if not search.is_empty() else ""),Vector2(48,157),15,MUTED,345)
	if filtered.is_empty():
		label(content,"Nothing here yet.",Vector2(448,255),48)
		label(content,"Install a game from All games." if installed_only else "Try another search or refresh the catalog in Settings.",Vector2(451,329),25,MUTED,650)
		button(content,"Show all games",Vector2(450,405),Vector2(235,54),func():search="";installed_only=false;refresh_view(),true).grab_focus()
		return
	if not filtered.any(func(g):return g.id==selected_id):selected_id=filtered[0].id
	var list=ScrollContainer.new();list.position=Vector2(48,196);list.size=Vector2(330,425);list.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;list.follow_focus=true;content.add_child(list)
	var rows=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;rows.add_theme_constant_override("separation",12);list.add_child(rows)
	var chosen: Dictionary={};var cards=[]
	for game in filtered:
		var info=library.install_info(game.id)
		var card=button(rows,"",Vector2.ZERO,Vector2(318,110),select_game.bind(game.id));card.custom_minimum_size=Vector2(318,110);cards.append(card)
		if game.id==selected_id:chosen=game;card.add_theme_stylebox_override("normal",style(Color("203628"),LIME))
		label(card,game.title,Vector2(19,15),29,WHITE,282)
		label(card,("INSTALLED  /  "+str(info.get("version",""))) if not info.is_empty() else "AVAILABLE  /  "+game.version,Vector2(20,68),16,LIME if not info.is_empty() else MUTED)
	var panel=Panel.new();panel.position=Vector2(410,128);panel.size=Vector2(822,490);panel.add_theme_stylebox_override("panel",style(Color("111e2c"),Color("2b3e4c")));panel.clip_contents=true;content.add_child(panel)
	cover_view=TextureRect.new();cover_view.position=Vector2(0,0);cover_view.size=Vector2(822,283);cover_view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;cover_view.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;cover_view.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_child(cover_view)
	show_cover(chosen)
	var veil=ColorRect.new();veil.color=Color(0,0,0,.17);veil.size=Vector2(822,283);veil.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_child(veil)
	label(panel," / ".join(chosen.tags).to_upper(),Vector2(26,253),16,LIME,760)
	label(panel,chosen.title,Vector2(26,302),43,WHITE,750)
	label(panel,chosen.description,Vector2(28,367),23,MUTED,510)
	label(panel,"CONTROLLER READY  ·  "+chosen.license,Vector2(28,462),14,MUTED)
	var info=library.install_info(chosen.id);var build=library.build_for(chosen)
	var update=not info.is_empty() and not build.is_empty() and info.sha256!=build.sha256
	var action="PLAY" if not info.is_empty() and not update else "UPDATE" if update else "INSTALL"
	if build.is_empty() and info.is_empty():action="LINUX ONLY"
	primary=button(panel,action,Vector2(566,371),Vector2(228,54),func():
		if action=="PLAY":library.launch(chosen)
		else:library.install_game(chosen)
	,true)
	primary.disabled=(library.busy and action!="PLAY") or (build.is_empty() and info.is_empty())
	button(panel,"Play installed" if update else "Game details" if appliance_mode else "View source",Vector2(566,435),Vector2(228,40),func():
		if update:library.launch(chosen)
		elif appliance_mode:show_game_details(chosen)
		else:OS.shell_open("https://github.com/"+chosen.repo)
	)
	for card in cards:card.focus_neighbor_right=card.get_path_to(primary)
	if (not popup or not popup.visible) and not (is_instance_valid(appliance_ui) and appliance_ui.visible):primary.grab_focus.call_deferred()
	queue_redraw()

func select_game(id: String):
	selected_id=id;refresh_view()

func show_cover(game: Dictionary):
	if covers.has(game.id):cover_view.texture=covers[game.id];return
	var cached="user://artwork/"+game.id+".jpg"
	if FileAccess.file_exists(cached):
		var img=Image.load_from_file(cached)
		if img:covers[game.id]=ImageTexture.create_from_image(img);cover_view.texture=covers[game.id];return
	if ResourceLoader.exists("res://"+game.cover):
		cover_view.texture=load("res://"+game.cover);covers[game.id]=cover_view.texture;return
	cover_http.cancel_request();cover_for=game.id;cover_http.request(Catalog.ART_URL+game.cover)

func cover_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200:return
	var img=Image.new()
	if img.load_jpg_from_buffer(body)!=OK:return
	covers[cover_for]=ImageTexture.create_from_image(img)
	var f=FileAccess.open("user://artwork/"+cover_for+".jpg",FileAccess.WRITE)
	if f:f.store_buffer(body)
	if selected_id==cover_for and is_instance_valid(cover_view):cover_view.texture=covers[cover_for]

func dialog(title: String, size=Vector2i(800,540)) -> Control:
	if popup:popup.queue_free()
	popup=PopupPanel.new();popup.size=size;popup.add_theme_stylebox_override("panel",style(Color("0e1c2b"),Color("4d6e76"),2));add_child(popup)
	var root=Control.new();root.custom_minimum_size=size;popup.add_child(root)
	label(root,title,Vector2(30,20),38)
	popup.popup_hide.connect(func():
		mapping=-1
		if is_instance_valid(primary):primary.grab_focus()
	)
	popup.popup_centered(size);return root

func show_search():
	var root=dialog("Find your next game",Vector2i(820,536))
	var input=LineEdit.new();input.position=Vector2(30,86);input.size=Vector2(760,52);input.text=search;input.placeholder_text="Search titles, genres or creators";root.add_child(input)
	input.text_submitted.connect(func(value):search=value.strip_edges();popup.hide();refresh_view())
	var chars="ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	for i in range(chars.length()):
		button(root,chars[i],Vector2(30+(i%10)*76,166+(i/10)*57),Vector2(66,47),func():input.insert_text_at_caret(chars[i]))
	button(root,"Space",Vector2(30,401),Vector2(142,45),func():input.insert_text_at_caret(" "))
	button(root,"Delete",Vector2(183,401),Vector2(142,45),func():input.text=input.text.left(-1);input.caret_column=input.text.length())
	button(root,"Clear",Vector2(336,401),Vector2(142,45),func():input.clear())
	button(root,"SEARCH",Vector2(492,401),Vector2(146,45),func():search=input.text.strip_edges();popup.hide();refresh_view(),true)
	button(root,"Back",Vector2(648,401),Vector2(142,45),func():popup.hide())
	label(root,"Use the keyboard or select letters with your controller.",Vector2(30,475),20,MUTED)
	input.grab_focus()

func show_settings():
	if appliance_mode:
		appliance_ui.show_settings();return
	var root=dialog("Console settings",Vector2i(740,530))
	label(root,library.connection,Vector2(32,80),22,LIME)
	button(root,"Refresh game catalog",Vector2(30,137),Vector2(680,48),func():popup.hide();library.refresh()).grab_focus()
	button(root,"Display: "+("Fullscreen" if fullscreen else "Windowed"),Vector2(30,198),Vector2(680,48),func():
		fullscreen=not fullscreen;DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		settings.set_value("display","fullscreen",fullscreen);settings.save("user://console.cfg");show_settings()
	)
	button(root,"Map controller buttons",Vector2(30,259),Vector2(680,48),show_mapping)
	button(root,"Submit a game",Vector2(30,320),Vector2(680,48),func():OS.shell_open("https://github.com/spiderwisp/fgc-console#add-a-game"))
	if "--kiosk" not in OS.get_cmdline_user_args():button(root,"Quit to desktop",Vector2(30,381),Vector2(329,48),func():get_tree().quit())
	button(root,"Back",Vector2(381,381),Vector2(329,48),func():popup.hide())
	label(root,"FGC Console 0.2.0  /  Community games, reviewed releases.",Vector2(32,463),19,MUTED)

func show_game_details(game: Dictionary):
	var root=dialog(game.title,Vector2i(820,400))
	label(root,game.description,Vector2(32,96),26,WHITE,750)
	label(root,"Source: github.com/"+game.repo+"\nLicense: "+game.license+"  /  Version: "+game.version,Vector2(32,225),22,MUTED,750)
	button(root,"Back",Vector2(32,322),Vector2(750,48),func():popup.hide()).grab_focus()

func show_mapping():
	var root=dialog("Controller setup",Vector2i(650,340));mapping=0
	map_label=label(root,"Press A / Select",Vector2(35,125),35,LIME)
	label(root,"Then press B / Back. D-pad navigation is automatic.",Vector2(35,199),21,MUTED)
	button(root,"Cancel",Vector2(35,256),Vector2(190,48),func():popup.hide())

func bind_controller():
	for i in range(2):
		var action=["ui_accept","ui_cancel"][i]
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton:InputMap.action_erase_event(action,event)
		var event=InputEventJoypadButton.new();event.button_index=controller_buttons[i];InputMap.action_add_event(action,event)

func _input(event):
	if mapping>=0 and event is InputEventJoypadButton and event.pressed:
		controller_buttons[mapping]=event.button_index;mapping+=1
		if mapping==2:
			mapping=-1;bind_controller();settings.set_value("input","buttons",controller_buttons);settings.save("user://console.cfg");popup.hide()
		else:map_label.text="Press B / Back"
		get_viewport().set_input_as_handled();return
	if event.is_action_pressed("ui_cancel") and popup and popup.visible:
		popup.hide();get_viewport().set_input_as_handled()

func game_started():
	Engine.max_fps=3;DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)

func game_finished():
	Engine.max_fps=60
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	get_window().grab_focus()

func _process(_dt):
	if not ready_ui:return
	status.text=library.phase+"  "+str(int(library.progress*100))+"%" if library.busy else library.message
	meter.visible=library.busy;meter.value=library.progress
	if library.game_pid<0:queue_redraw()

func _draw():
	draw_rect(Rect2(0,0,1280,720),Color("091320"))
	for i in range(9):draw_line(Vector2(850+i*80,0),Vector2(300+i*80,720),Color(.1,.2,.25,.16),1)
	var o=Vector2(49,37)
	draw_colored_polygon(PackedVector2Array([o,o+Vector2(36,0),o+Vector2(47,12),o+Vector2(14,12),o+Vector2(14,22),o+Vector2(36,22),o+Vector2(23,35),o+Vector2(14,35),o+Vector2(14,46),o+Vector2(0,57)]),LIME)
	draw_line(Vector2(48,106),Vector2(1232,106),Color("26394a"))
	draw_line(Vector2(48,682),Vector2(1232,682),Color("26394a"))
	draw_string(FONT,Vector2(48,708),"D-PAD / ARROWS  BROWSE     A / ENTER  SELECT     B / ESC  BACK",HORIZONTAL_ALIGNMENT_LEFT,-1,17,MUTED)
	if library:
		draw_string(FONT,Vector2(913,708),library.connection,HORIZONTAL_ALIGNMENT_RIGHT,318,17,MUTED)
	var now=Time.get_datetime_dict_from_system()
	draw_string(FONT,Vector2(952,71),"%02d:%02d" % [now.hour,now.minute],HORIZONTAL_ALIGNMENT_LEFT,-1,27,MUTED)
