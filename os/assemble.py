#!/usr/bin/python3
import fcntl,hashlib,json,os,shutil,subprocess,zipfile
from pathlib import Path

ROOT=Path('/build/rootfs');ISO=Path('/build/iso');SRC=Path('/src');OUT=Path('/out')
VERSION='0.2.0'

def run(*args):subprocess.run(args,check=True)
def write(path,text,mode=0o644):
    dest=ROOT/path;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(text,encoding='utf-8');dest.chmod(mode)

build_lock=open('/build/.build-lock','w')
fcntl.flock(build_lock,fcntl.LOCK_EX)
if ROOT.exists() and os.environ.get('FGC_REUSE_ROOT')!='1':shutil.rmtree(ROOT)
ROOT.mkdir(parents=True,exist_ok=True)
if not (ROOT/'usr/bin/python3').exists():
    producer=subprocess.Popen(['tar','--one-file-system',*['--exclude=./'+p for p in ['build','src','out','artifacts','dev','proc','sys','run','tmp','etc/hosts','etc/hostname','etc/resolv.conf']],'-C','/','-cpf','-','.'],stdout=subprocess.PIPE)
    subprocess.run(['tar','-C',str(ROOT),'-xpf','-'],stdin=producer.stdout,check=True);producer.stdout.close()
    if producer.wait()!=0:raise RuntimeError('Could not assemble the Ubuntu filesystem.')
for d in ('dev','proc','sys','run','tmp','mnt','home/fgc','etc/fgc','usr/share/fgc','usr/lib/fgc','var/lib/fgc'):(ROOT/d).mkdir(parents=True,exist_ok=True)
for marker in ('.dockerenv','run/.containerenv','etc/machine-info'):(ROOT/marker).unlink(missing_ok=True)
(ROOT/'tmp').chmod(0o1777)
for name in ('system.py','fgcctl','seed.py','session.sh'):
    write('usr/lib/fgc/'+name,(SRC/'os'/name).read_text(encoding='utf-8-sig'),0o755)
write('usr/share/fgc/openbox.xml',(SRC/'os/openbox.xml').read_text(encoding='utf-8-sig'))
for path in (SRC/'os/services').glob('*.service'):write('etc/systemd/system/'+path.name,path.read_text(encoding='utf-8-sig'))
write('etc/fgc/os.json',json.dumps({'name':'FGC OS','version':VERSION,'base':'Ubuntu 26.04 LTS','architecture':'x86_64'}))
write('etc/hostname','fgc\n')
write('etc/hosts','127.0.0.1 localhost\n127.0.1.1 fgc\n::1 localhost ip6-localhost\n')
write('etc/machine-id','')
write('etc/fstab','')
write('etc/issue','FGC Console\n')
write('etc/locale.conf','LANG=C.UTF-8\n')
write('etc/default/locale','LANG=C.UTF-8\n')
write('etc/default/grub','GRUB_DEFAULT=0\nGRUB_TIMEOUT=2\nGRUB_DISTRIBUTOR="FGC Console"\nGRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 systemd.show_status=false"\nGRUB_DISABLE_OS_PROBER=true\n')
write('etc/lightdm/lightdm.conf.d/60-fgc.conf','[Seat:*]\nautologin-user=fgc\nautologin-user-timeout=0\nautologin-session=fgc\nuser-session=fgc\nallow-guest=false\ngreeter-hide-users=true\n')
write('usr/share/xsessions/fgc.desktop','[Desktop Entry]\nName=FGC Console\nType=Application\nExec=/usr/lib/fgc/session.sh\nDesktopNames=FGC\n')
write('etc/NetworkManager/conf.d/10-fgc.conf','[main]\nplugins=keyfile\n[device]\nwifi.scan-rand-mac-address=yes\n')
write('etc/NetworkManager/conf.d/10-globally-managed-devices.conf','[keyfile]\nunmanaged-devices=\n')
write('etc/X11/xorg.conf.d/10-fgc.conf','Section "ServerFlags"\n Option "DontVTSwitch" "true"\n Option "DontZap" "true"\nEndSection\n')
write('etc/systemd/logind.conf.d/fgc.conf','[Login]\nHandlePowerKey=poweroff\nHandleLidSwitch=ignore\nIdleAction=ignore\nNAutoVTs=0\nReserveVT=0\n')
write('etc/apt/apt.conf.d/20auto-upgrades','APT::Periodic::Update-Package-Lists "0";\nAPT::Periodic::Unattended-Upgrade "0";\n')
(ROOT/'etc/resolv.conf').unlink(missing_ok=True);(ROOT/'etc/resolv.conf').symlink_to('/run/NetworkManager/resolv.conf')
(ROOT/'usr/sbin/policy-rc.d').unlink(missing_ok=True)
for service in ('fgc-system.service','fgc-seed.service','NetworkManager.service','lightdm.service'):
    run('systemctl','--root='+str(ROOT),'enable',service)
run('systemctl','--root='+str(ROOT),'set-default','graphical.target')
for service in ('pipewire.socket','pipewire-pulse.socket','wireplumber.service'):
    run('systemctl','--root='+str(ROOT),'--global','enable',service)
write('usr/share/plymouth/themes/fgc/fgc.plymouth','[Plymouth Theme]\nName=FGC\nDescription=Framework Gaming Console\nModuleName=script\n[script]\nImageDir=/usr/share/plymouth/themes/fgc\nScriptFile=/usr/share/plymouth/themes/fgc/fgc.script\n')
write('usr/share/plymouth/themes/fgc/fgc.script','''Window.SetBackgroundTopColor(0.035,0.075,0.125);
Window.SetBackgroundBottomColor(0.035,0.075,0.125);
logo=Image.Text("FGC",0.70,0.94,0.47,"DejaVu Sans Bold 72");
sprite=Sprite(logo);sprite.SetX(Window.GetWidth()/2-logo.GetWidth()/2);sprite.SetY(Window.GetHeight()/2-logo.GetHeight()/2-20);
title=Image.Text("FRAMEWORK GAMING CONSOLE",0.57,0.64,0.71,"DejaVu Sans 16");
caption=Sprite(title);caption.SetX(Window.GetWidth()/2-title.GetWidth()/2);caption.SetY(Window.GetHeight()/2+65);
''')
theme=ROOT/'usr/share/plymouth/themes/default.plymouth';theme.unlink(missing_ok=True);theme.symlink_to('/usr/share/plymouth/themes/fgc/fgc.plymouth')
version_dir=ROOT/'opt/fgc/versions'/('v'+VERSION);version_dir.mkdir(parents=True,exist_ok=True)
shutil.copy2('/artifacts/FGCConsole.x86_64',version_dir/'FGCConsole.x86_64');(version_dir/'FGCConsole.x86_64').chmod(0o755)
current=ROOT/'opt/fgc/current';current.unlink(missing_ok=True);current.symlink_to('/opt/fgc/versions/v'+VERSION)
game=json.loads((SRC/'catalog/games.json').read_text())['games'][0];build=game['platforms']['linux-x86_64']
archive=Path('/artifacts/DeepSignal-Linux.zip')
if hashlib.file_digest(archive.open('rb'),'sha256').hexdigest()!=build['sha256']:raise ValueError('The bundled game checksum does not match the catalog.')
seed=ROOT/'usr/share/fgc/seed';dest=seed/'games'/game['id']/build['sha256'];dest.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(archive) as z:
    for info in z.infolist():
        rel=Path(info.filename)
        if rel.is_absolute() or '..' in rel.parts:raise ValueError('Unsafe bundled game path')
    z.extractall(dest)
(dest/build['executable']).chmod(0o755)
entry={**build,'version':game['version']};(seed/'installed.json').write_text(json.dumps({game['id']:entry}))
os.chown(ROOT/'home/fgc',1000,1000)
for folder in ('proc','sys','dev'):
    run('mount','--bind','/'+folder,str(ROOT/folder))
try:
    run('chroot',str(ROOT),'usermod','--shell','/bin/bash','fgc')
    run('chroot',str(ROOT),'update-initramfs','-u','-k','all')
finally:
    for folder in ('dev','sys','proc'):run('umount',str(ROOT/folder))
for p in (ROOT/'var/log').rglob('*'):
    if p.is_file() and not p.is_symlink():p.write_bytes(b'')
(ISO/'live').mkdir(parents=True,exist_ok=True);(ISO/'boot/grub').mkdir(parents=True,exist_ok=True)
kernel=sorted((ROOT/'boot').glob('vmlinuz-*'))[-1];version=kernel.name.removeprefix('vmlinuz-')
shutil.copy2(kernel,ISO/'live/vmlinuz');shutil.copy2(ROOT/'boot'/('initrd.img-'+version),ISO/'live/initrd')
(ISO/'boot/grub/grub.cfg').write_text('''set timeout=3
set default=0
menuentry 'Install or repair FGC Console' {
    search --no-floppy --label FGCOS --set=root
    linux /live/vmlinuz boot=live fgc.live=1 quiet splash loglevel=3 systemd.show_status=false
    initrd /live/initrd
}
menuentry 'FGC installer - graphics compatibility' {
    search --no-floppy --label FGCOS --set=root
    linux /live/vmlinuz boot=live fgc.live=1 fgc.graphics=safe quiet splash
    initrd /live/initrd
}
''')
efi=Path('/build/efi.img');efi.write_bytes(b'\0'*(16*1024*1024))
run('mkfs.vfat',str(efi));run('mmd','-i',str(efi),'::/EFI','::/EFI/BOOT','::/EFI/ubuntu')
cfg=Path('/build/efi-grub.cfg');cfg.write_text('search --no-floppy --label FGCOS --set=root\nset prefix=($root)/boot/grub\nconfigfile $prefix/grub.cfg\n')
for directory in ('BOOT','ubuntu'):
    folder=ISO/'EFI'/directory;folder.mkdir(parents=True,exist_ok=True)
    shutil.copy2(ROOT/'usr/lib/shim/shimx64.efi.signed.latest',folder/('BOOTX64.EFI' if directory=='BOOT' else 'shimx64.efi'))
    shutil.copy2(ROOT/'usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed',folder/'grubx64.efi')
    shutil.copy2(ROOT/'usr/lib/shim/mmx64.efi',folder/'mmx64.efi');shutil.copy2(cfg,folder/'grub.cfg')
    run('mcopy','-i',str(efi),str(ROOT/'usr/lib/shim/shimx64.efi.signed.latest'),'::/EFI/'+directory+('/BOOTX64.EFI' if directory=='BOOT' else '/shimx64.efi'))
    run('mcopy','-i',str(efi),str(ROOT/'usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed'),'::/EFI/'+directory+'/grubx64.efi')
    run('mcopy','-i',str(efi),str(ROOT/'usr/lib/shim/mmx64.efi'),'::/EFI/'+directory+'/mmx64.efi')
    run('mcopy','-i',str(efi),str(cfg),'::/EFI/'+directory+'/grub.cfg')
run('mksquashfs',str(ROOT),str(ISO/'live/filesystem.squashfs'),'-noappend','-comp','zstd','-Xcompression-level','15','-processors','4')
OUT.mkdir(parents=True,exist_ok=True)
image=OUT/('FGC-OS-'+VERSION+'-amd64.iso')
run('xorriso','-as','mkisofs','-r','-J','-V','FGCOS','-o',str(image),'-append_partition','2','0xef',str(efi),'-appended_part_as_gpt','-e','--interval:appended_partition_2:all::','-no-emul-boot',str(ISO))
digest=hashlib.file_digest(image.open('rb'),'sha256').hexdigest();(OUT/'SHA256SUMS').write_text(digest+'  '+image.name+'\n')
print('FGC ISO ready:',image.stat().st_size,'bytes',digest)
