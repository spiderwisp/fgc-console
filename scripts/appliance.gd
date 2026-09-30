extends Control

var home
var service
var page: Control
var mode="boot"
var first_run=true
var live=false
var initialized=false
var preview=false
var job_title=""
var stage_label: Label
var job_meter: ProgressBar
var password_input: LineEdit
var keyboard_mode=0
var keyboard_keys: Control
var network_ssid=""
var display_deadline=0.0
var waiting_for_start=false

func setup(owner_home,system_service):
	home=owner_home;service=system_service;theme=home.theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	service.received.connect(response)
	visibility_changed.connect(func():
		if not visible:home.suspend_home_focus(false)
	)
	preview="--appliance-preview" in OS.get_cmdline_user_args()
	first_run=not home.settings.get_value("appliance","setup_complete",false)
	clear("Starting your console","FGC OS")
	if preview:
		initialized=true;show_setup()

func clear(title: String, subtitle=""):
	visible=true
	home.suspend_home_focus(true)
	if page:page.free()
	page=Control.new();page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(page)
	var bg=ColorRect.new();bg.color=Color("091320");bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);page.add_child(bg)
	home.label(page,"FGC",Vector2(64,36),39,home.LIME)
	home.label(page,title,Vector2(64,108),45,home.WHITE,1120)
	home.label(page,subtitle,Vector2(66,170),22,home.MUTED,1110)

func choice(text: String,x: float,y: float,action: Callable,width=550.0,accent=false) -> Button:
	return home.button(page,text,Vector2(x,y),Vector2(width,56),action,accent)

func request(action: String,args: Dictionary={}):
	if preview:
		show_error("This is a layout preview. System controls run on FGC OS.");return
	if not service.request(action,args):show_error("The console service is unavailable. Restart the console or use USB repair.")

func show_setup():
	mode="setup";clear("Make yourself at home","Connect your console, check your TV and controller, then start playing. You can change these settings later.")
	choice("Wi-Fi & network",64,260,show_network).grab_focus()
	choice("Picture & resolution",664,260,show_displays)
	choice("Sound & volume",64,344,show_audio)
	choice("Set up controller",664,344,home.show_mapping)
	choice("START PLAYING",64,495,func():
		home.settings.set_value("appliance","setup_complete",true);home.settings.save("user://console.cfg");first_run=false;visible=false;home.refresh_view()
	,1150,true)
	home.label(page,"Deep Signal is included. Internet is optional for your first dive.",Vector2(66,580),23,home.MUTED)

func show_settings():
	mode="settings";clear("Console settings","FGC OS 0.2.0  /  Your games, your console.")
	choice("Wi-Fi & network",64,245,show_network).grab_focus()
	choice("Picture & resolution",664,245,show_displays)
	choice("Sound & volume",64,327,show_audio)
	choice("Controller buttons",664,327,home.show_mapping)
	choice("System updates",64,409,show_updates)
	choice("Recovery",664,409,show_recovery)
	choice("Refresh game catalog",64,491,func():home.library.refresh();visible=false)
	choice("Power",664,491,show_power)
	choice("Back",64,594,back,1150)

func back():
	if live:show_installer()
	elif first_run:show_setup()
	elif mode!="settings":show_settings()
	else:visible=false;home.refresh_view()

func show_installer():
	mode="disks";clear("Welcome to FGC","Install the complete console on your internal SSD. Deep Signal is included, and installation works offline.")
	home.label(page,"Looking for internal drives…",Vector2(66,267),28,home.LIME)
	request("disks")

func disk_list(disks: Array):
	mode="disks";clear("Install your console","Choose the internal SSD for FGC. USB and mounted drives are excluded.")
	if disks.is_empty():home.label(page,"No available internal SSD found. Fit an SSD of at least 32 GiB, then refresh.",Vector2(66,260),28,home.WHITE,1100)
	for i in range(mini(disks.size(),4)):
		var disk=disks[i]
		var text=str(disk.name)+"  /  "+str(snappedf(float(disk.size)/1073741824.0,.1))+" GiB  /  "+str(disk.device)
		choice(text,64,245+i*76,confirm_install.bind(disk),1150).grab_focus()
	choice("Refresh drives",64,582,show_installer,345)
	choice("Try FGC from USB",465,582,func():visible=false;home.refresh_view(),345)
	choice("Shut down",866,582,func():request("shutdown"),348)

func confirm_install(disk: Dictionary):
	mode="confirm_install";clear("Your console starts here",str(disk.name)+"  /  "+str(snappedf(float(disk.size)/1073741824.0,.1))+" GiB  /  "+str(disk.device))
	home.label(page,"A fresh installation erases everything on this selected SSD. FGC will install automatically after you confirm.",Vector2(66,257),30,home.WHITE,1090)
	choice("ERASE THIS SSD & INSTALL FGC",64,415,func():job_title="Installing FGC";show_working();request("install",{"token":disk.token,"confirm":"INSTALL FGC","repair":false}),1150,true)
	if disk.repair:
		choice("Repair FGC — keep games & saves",64,499,func():job_title="Repairing FGC";show_working();request("install",{"token":disk.token,"confirm":"INSTALL FGC","repair":true}),1150)
	choice("Back",64,594,show_installer,1150).grab_focus()

func show_network():
	mode="networks";clear("Connect to your world","Ethernet connects automatically. Choose a Wi-Fi network, or continue offline.")
	home.label(page,"Scanning Wi-Fi…",Vector2(66,262),28,home.LIME);request("networks")

func network_list(networks: Array):
	mode="networks";clear("Wi-Fi & network",str(service.last_status.get("network",""))+"  /  Ethernet connects automatically.")
	var scroll=ScrollContainer.new();scroll.position=Vector2(64,225);scroll.size=Vector2(1150,330);scroll.follow_focus=true;page.add_child(scroll)
	var rows=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;rows.add_theme_constant_override("separation",12);scroll.add_child(rows)
	for network in networks:
		var title=str(network.ssid)+"  /  "+str(network.signal)+"%"+("  CONNECTED" if network.active else "")
		var b=home.button(rows,title,Vector2.ZERO,Vector2(1100,54),func():
			network_ssid=network.ssid
			if network.security.is_empty() or network.security=="--":connect_network("")
			else:show_password()
		)
		b.custom_minimum_size=Vector2(1100,54)
		if network==networks[0]:b.grab_focus()
	if networks.is_empty():home.label(page,"No Wi-Fi networks found. Check that a Wi-Fi module and antennas are installed.",Vector2(66,267),28,home.WHITE,1100)
	choice("Scan again",64,594,show_network,550)
	choice("Back",664,594,back).grab_focus()

func show_password():
	mode="password";clear("Join "+network_ssid,"Enter the Wi-Fi password using your controller or a keyboard.")
	password_input=LineEdit.new();password_input.position=Vector2(64,220);password_input.size=Vector2(1150,55);password_input.secret=true;password_input.max_length=128;page.add_child(password_input)
	password_input.text_submitted.connect(connect_network)
	keyboard_keys=Control.new();page.add_child(keyboard_keys);draw_keys()
	choice("abc / ABC / symbols",64,559,func():keyboard_mode=(keyboard_mode+1)%3;draw_keys(),345)
	choice("Delete",465,559,func():password_input.text=password_input.text.left(-1),345)
	choice("Show / hide",866,559,func():password_input.secret=not password_input.secret,348)
	choice("CONNECT",64,633,func():connect_network(password_input.text),550,true)
	choice("Back",664,633,show_network)
	password_input.grab_focus()

func draw_keys():
	for child in keyboard_keys.get_children():child.free()
	var chars=["abcdefghijklmnopqrstuvwxyz0123456789 ","ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ","!@#$%^&*()-_=+[]{};:'\",.<>/?\\|`~ "][keyboard_mode]
	for i in range(chars.length()):
		var character=chars[i]
		home.button(keyboard_keys,"Space" if character==" " else character,Vector2(64+(i%10)*115,304+(i/10)*59),Vector2(105,49),func():password_input.insert_text_at_caret(character))

func connect_network(password: String):
	job_title="Connecting to Wi-Fi";show_working();request("connect",{"ssid":network_ssid,"password":password})

func show_audio():
	mode="audio";clear("Sound & volume","Choose your TV, monitor, or connected speakers.");request("audio")

func audio_list(outputs: Array):
	mode="audio";clear("Sound & volume","Choose an output. Your volume and output selection are saved by the audio system.")
	for i in range(mini(outputs.size(),4)):
		var sink=outputs[i];var y=245+i*75
		choice(str(sink.name).left(55)+("  ✓" if sink.active else ""),64,y,func():request("audio_set",{"id":int(sink.id),"volume":int(sink.volume),"mute":false}),680).grab_focus()
		choice("−",768,y,func():request("audio_set",{"id":int(sink.id),"volume":maxi(0,int(sink.volume)-10),"mute":false}),70)
		home.label(page,str(sink.volume)+"%",Vector2(859,y+13),25,home.LIME)
		choice("+",935,y,func():request("audio_set",{"id":int(sink.id),"volume":mini(100,int(sink.volume)+10),"mute":false}),70)
		choice("Unmute" if sink.mute else "Mute",1030,y,func():request("audio_set",{"id":int(sink.id),"volume":int(sink.volume),"mute":not sink.mute}),184)
	if outputs.is_empty():home.label(page,"No audio outputs detected. Connect your display or USB audio device, then try again.",Vector2(66,257),28,home.WHITE,1100)
	choice("Refresh",64,594,show_audio,550);choice("Back",664,594,back)

func show_displays():
	mode="displays";clear("Picture & resolution","Choose the resolution your display should use.");request("displays")

func display_list(displays: Array):
	mode="displays";clear("Picture & resolution","Changes revert after 20 seconds unless you keep them. Game graphics settings remain inside each game.")
	var scroll=ScrollContainer.new();scroll.position=Vector2(64,230);scroll.size=Vector2(1150,334);scroll.follow_focus=true;page.add_child(scroll)
	var rows=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;rows.add_theme_constant_override("separation",10);scroll.add_child(rows)
	for screen in displays:
		for resolution in screen.modes:
			var b=home.button(rows,screen.name+"  /  "+resolution+("  CURRENT" if resolution==screen.current else ""),Vector2.ZERO,Vector2(1100,52),func():request("display_set",{"output":screen.name,"mode":resolution}))
			b.custom_minimum_size=Vector2(1100,52)
	choice("Back",64,594,back,1150).grab_focus()

func confirm_picture():
	mode="picture_confirm";display_deadline=Time.get_ticks_msec()*.001+20.5
	clear("Does the picture look right?","Keep this resolution, or wait for the previous setting to return.")
	choice("KEEP THIS RESOLUTION",64,300,func():request("display_confirm"),1150,true).grab_focus()
	stage_label=home.label(page,"",Vector2(66,411),30,home.LIME)

func show_updates():
	mode="updates";clear("Keep your console ready","Updates include Ubuntu security fixes, drivers, and the latest FGC launcher. Games update individually in your library.")
	home.label(page,"Keep the console powered on while an update runs. Restart when it finishes.",Vector2(66,264),29,home.WHITE,1100)
	choice("CHECK & INSTALL UPDATES",64,398,func():job_title="Updating your console";show_working();request("update"),1150,true).grab_focus()
	choice("Back",64,594,back,1150)

func show_recovery():
	mode="recovery";clear("Your games stay with you","Repair FGC using the same USB installer.")
	home.label(page,"1. Flash the latest FGC installer to a USB stick.\n2. Shut down, insert it, and power on. Use F12 if the USB does not start.\n3. Select your existing FGC SSD and choose Repair FGC.\n\nRepair replaces the console system while keeping the games, saves, and settings on the separate data partition. A fresh installation erases the whole selected SSD.",Vector2(66,247),27,home.WHITE,1110)
	choice("Shut down",64,594,func():request("shutdown"),550)
	choice("Back",664,594,back).grab_focus()

func show_power():
	mode="power";clear("Until your next adventure","Finish any downloads before shutting down.")
	choice("SHUT DOWN",64,284,func():request("shutdown"),1150,true).grab_focus()
	choice("Restart console",64,376,func():request("reboot"),1150)
	choice("Back",64,594,back,1150)

func show_working():
	mode="working";waiting_for_start=true;clear(job_title,"Keep the console powered on.")
	stage_label=home.label(page,"Preparing…",Vector2(66,280),30,home.LIME,1100)
	job_meter=ProgressBar.new();job_meter.position=Vector2(64,400);job_meter.size=Vector2(1150,15);job_meter.max_value=1;job_meter.show_percentage=false;page.add_child(job_meter)

func show_error(message: String):
	mode="error";clear("That did not finish","Your console is still here. Check the message below and try again.")
	home.label(page,message,Vector2(66,263),28,home.WHITE,1100)
	choice("Back",64,594,back,1150).grab_focus()

func response(action: String,result: Dictionary):
	if not result.get("ok"):
		if action!="status" or not initialized:show_error(str(result.get("error","Operation failed.")))
		return
	if action=="status":
		if not initialized:
			initialized=true;live=result.live
			if live:show_installer()
			elif first_run:show_setup()
			else:visible=false
		if mode=="working" and not waiting_for_start:
			var job=result.job
			stage_label.text=job.stage;job_meter.value=job.progress
			if not str(job.error).is_empty():show_error(job.error)
			elif job.done and not job.busy:
				mode="finished"
				choice("SHUT DOWN & REMOVE USB" if live and "FGC" in job_title else "Back to console",64,594,func():
					if live and "FGC" in job_title:request("shutdown")
					else:back()
				,1150,true).grab_focus()
	elif action=="disks":disk_list(result.disks)
	elif action=="networks":network_list(result.networks)
	elif action in ["audio","audio_set"]:audio_list(result.outputs)
	elif action=="displays":display_list(result.displays)
	elif action=="display_set":confirm_picture()
	elif action=="display_confirm":show_displays()
	elif action in ["install","connect","update"]:waiting_for_start=false

func _process(_delta):
	if mode=="picture_confirm":
		var remaining=ceili(display_deadline-Time.get_ticks_msec()*.001)
		stage_label.text="Reverting in "+str(clampi(remaining,0,20))+" seconds"
		if remaining<=0:show_displays()

func _input(event):
	if visible and event.is_action_pressed("ui_cancel") and not (is_instance_valid(home.popup) and home.popup.visible):
		if mode not in ["boot","working","confirm_install","setup","disks"]:back();get_viewport().set_input_as_handled()
