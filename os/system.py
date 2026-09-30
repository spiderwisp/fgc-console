#!/usr/bin/python3
import hashlib
import json
import os
import re
import shutil
import socket
import socketserver
import struct
import subprocess
import tarfile
import tempfile
import threading
import time
import urllib.request
from pathlib import Path

RUN=Path('/run/fgc')
TARGET=Path('/mnt/fgc-target')
MEDIA=Path('/run/live/medium/live/filesystem.squashfs')
LIVE='fgc.live=1' in Path('/proc/cmdline').read_text().split()
JOB={'busy':False,'stage':'','progress':0,'error':'','done':False}
LOCK=threading.Lock()
DISPLAY_LOCK=threading.Lock()
DISPLAY_PENDING=None
DISK_TOKENS={}

def command(args,timeout=45,input=None,check=True):
    p=subprocess.run(args,input=input,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout)
    if check and p.returncode:
        raise RuntimeError((p.stderr.strip() or p.stdout.strip() or 'Operation failed')[-1200:])
    return p.stdout

def user_command(args,timeout=20):
    env=['XDG_RUNTIME_DIR=/run/user/1000','DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus','DISPLAY=:0','XAUTHORITY=/home/fgc/.Xauthority']
    session=Path('/run/user/1000/fgc-display.json')
    if session.exists():
        data=json.loads(session.read_text())
        for key in ('DISPLAY','XAUTHORITY'):
            if isinstance(data.get(key),str) and 0<len(data[key])<300:
                env=[e for e in env if not e.startswith(key+'=')]+[key+'='+data[key]]
    return command(['/usr/sbin/runuser','-u','fgc','--','/usr/bin/env',*env,*args],timeout)

def progress(stage,amount):
    with LOCK:JOB.update(stage=stage,progress=amount)

def start_job(fn,*args):
    with LOCK:
        if JOB['busy']:raise ValueError('Another system operation is running.')
        JOB.update(busy=True,stage='Preparing',progress=0,error='',done=False)
    def run():
        try:
            fn(*args)
            with LOCK:JOB.update(busy=False,done=True,progress=1)
        except Exception as e:
            with LOCK:JOB.update(busy=False,error=str(e),done=False)
    threading.Thread(target=run,daemon=True).start()
    return {'started':True}

def block_devices():
    return json.loads(command(['lsblk','--json','--tree','--bytes','--output','PATH,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS,RM,TRAN,SERIAL,MODEL,RO']))['blockdevices']

def descendants(node):
    yield node
    for child in node.get('children',[]):yield from descendants(child)

def eligible_disks():
    result=[]
    for disk in block_devices():
        if disk['type']!='disk' or disk.get('rm') or disk.get('ro') or disk.get('tran')=='usb':continue
        if int(disk['size'])<32*1024**3 or not re.fullmatch(r'/dev/(nvme\d+n\d+|sd[a-z]+|vd[a-z]+)',disk['path']):continue
        if any(any(m for m in node.get('mountpoints',[]) or []) for node in descendants(disk)):continue
        identity='|'.join(str(disk.get(k,'')) for k in ('path','size','serial','model'))
        token=hashlib.sha256(identity.encode()).hexdigest()
        labels={p.get('label'):p['path'] for p in disk.get('children',[]) if p.get('label')}
        repair=all(k in labels for k in ('FGCEFI','FGCSYSTEM','FGCDATA'))
        DISK_TOKENS[token]=(time.monotonic(),identity)
        result.append({'device':disk['path'],'name':str(disk.get('model') or 'Internal SSD').strip(),'size':disk['size'],'serial':disk.get('serial') or '', 'token':token,'repair':repair})
    return result

def selected_disk(token):
    if not LIVE or not MEDIA.is_file():raise ValueError('Installation is only available from the FGC USB installer.')
    issued=DISK_TOKENS.get(token)
    if not issued or time.monotonic()-issued[0]>180:raise ValueError('Refresh the drive list and confirm the drive again.')
    for disk in eligible_disks():
        if disk['token']==token:return disk['device']
    raise ValueError('The selected drive changed or is in use. Nothing was erased.')

def partition_path(disk,n):return disk+('p' if disk[-1].isdigit() else '')+str(n)

def install(token,repair):
    disk=selected_disk(token)
    progress('Checking installation drive',.03)
    if repair:
        node=next(d for d in block_devices() if d['path']==disk)
        labels={p.get('label'):p['path'] for p in node.get('children',[])}
        if not all(k in labels for k in ('FGCEFI','FGCSYSTEM','FGCDATA')):raise ValueError('This drive does not contain an FGC installation.')
        efi,system,data=[labels[k] for k in ('FGCEFI','FGCSYSTEM','FGCDATA')]
        TARGET.mkdir(parents=True,exist_ok=True)
        command(['mount','-o','ro',system,str(TARGET)])
        try:
            if not (TARGET/'etc/fgc/os.json').is_file():raise ValueError('The system partition is not an FGC installation.')
        finally:command(['umount',str(TARGET)])
    else:
        command(['wipefs','--all',disk])
        command(['sgdisk','--zap-all','--new=1:0:+512M','--typecode=1:ef00','--new=2:0:+16G','--typecode=2:8300','--new=3:0:0','--typecode=3:8300',disk])
        command(['partprobe',disk]);command(['udevadm','settle'])
        efi,system,data=[partition_path(disk,n) for n in (1,2,3)]
        command(['mkfs.vfat','-F','32','-n','FGCEFI',efi])
        command(['mkfs.ext4','-F','-L','FGCDATA',data],timeout=180)
    progress('Preparing FGC system partition',.10)
    command(['mkfs.ext4','-F','-L','FGCSYSTEM',system],timeout=180)
    TARGET.mkdir(parents=True,exist_ok=True)
    command(['mount',system,str(TARGET)])
    mounted=[TARGET]
    try:
        progress('Installing the console and offline game',.20)
        command(['unsquashfs','-f','-no-progress','-d',str(TARGET),str(MEDIA)],timeout=1800)
        for folder in ('boot/efi','home','dev','proc','sys','run'):(TARGET/folder).mkdir(parents=True,exist_ok=True)
        command(['mount',efi,str(TARGET/'boot/efi')]);mounted.append(TARGET/'boot/efi')
        command(['mount',data,str(TARGET/'home')]);mounted.append(TARGET/'home')
        (TARGET/'home/fgc').mkdir(exist_ok=True);os.chown(TARGET/'home/fgc',1000,1000)
        uuids={name:command(['blkid','-s','UUID','-o','value',dev]).strip() for name,dev in [('root',system),('efi',efi),('home',data)]}
        (TARGET/'etc/fstab').write_text('UUID={root} / ext4 defaults,noatime 0 1\nUUID={efi} /boot/efi vfat umask=0077 0 1\nUUID={home} /home ext4 defaults,noatime 0 2\n'.format(**uuids))
        (TARGET/'etc/machine-id').write_text('')
        (TARGET/'etc/hostname').write_text('fgc\n')
        (TARGET/'etc/resolv.conf').unlink(missing_ok=True)
        (TARGET/'etc/resolv.conf').symlink_to('/run/NetworkManager/resolv.conf')
        progress('Installing the UEFI bootloader',.80)
        boot=TARGET/'boot';(boot/'grub').mkdir(exist_ok=True)
        shutil.copytree(TARGET/'usr/lib/grub/x86_64-efi',boot/'grub/x86_64-efi',dirs_exist_ok=True)
        version=sorted((boot).glob('vmlinuz-*'))[-1].name.removeprefix('vmlinuz-')
        normal=f'root=UUID={uuids["root"]} ro quiet splash loglevel=3 systemd.show_status=false'
        (boot/'grub/grub.cfg').write_text(f'''set timeout=2
set default=0
menuentry 'FGC Console' {{
    search --no-floppy --fs-uuid --set=root {uuids['root']}
    linux /boot/vmlinuz-{version} {normal}
    initrd /boot/initrd.img-{version}
}}
menuentry 'FGC Console - graphics recovery' {{
    search --no-floppy --fs-uuid --set=root {uuids['root']}
    linux /boot/vmlinuz-{version} {normal} fgc.graphics=safe
    initrd /boot/initrd.img-{version}
}}
''')
        cfg=f"search --no-floppy --fs-uuid --set=root {uuids['root']}\nset prefix=($root)/boot/grub\nconfigfile $prefix/grub.cfg\n"
        for name in ('BOOT','ubuntu'):
            dest=boot/'efi/EFI'/name;dest.mkdir(parents=True,exist_ok=True)
            shim=TARGET/'usr/lib/shim/shimx64.efi.signed.latest'
            grub=TARGET/'usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed'
            shutil.copy2(shim,dest/('BOOTX64.EFI' if name=='BOOT' else 'shimx64.efi'))
            shutil.copy2(grub,dest/'grubx64.efi');(dest/'grub.cfg').write_text(cfg)
            mok=TARGET/'usr/lib/shim/mmx64.efi'
            if mok.exists():shutil.copy2(mok,dest/'mmx64.efi')
        if Path('/sys/firmware/efi/efivars').is_dir():
            existing=command(['efibootmgr','--verbose'],check=False)
            partuuid=command(['blkid','-s','PARTUUID','-o','value',efi]).strip().lower()
            if not any('FGC Console' in line and 'gpt,'+partuuid+',' in line.lower() for line in existing.splitlines()):
                efi_partition=re.search(r'(\d+)$',efi).group(1)
                command(['efibootmgr','--create','--disk',disk,'--part',efi_partition,'--label','FGC Console','--loader',r'\EFI\ubuntu\shimx64.efi'],check=False)
        progress('Finishing installation',.95)
        command(['sync'],timeout=120)
    finally:
        for path in reversed(mounted):command(['umount',str(path)],check=False)
    progress('FGC is installed. Remove the USB after shutdown, then turn on your console.',1)

def networks():
    command(['nmcli','device','wifi','rescan'],check=False)
    out=command(['nmcli','-t','--escape','yes','-f','IN-USE,SSID,SIGNAL,SECURITY','device','wifi','list'])
    seen=set();result=[]
    for line in out.splitlines():
        fields=re.split(r'(?<!\\):',line)
        if len(fields)<4:continue
        ssid=fields[1].replace('\\:',':').replace('\\\\','\\')
        if not ssid or ssid in seen:continue
        seen.add(ssid);result.append({'ssid':ssid,'signal':int(fields[2] or 0),'security':fields[3],'active':fields[0]=='*'})
    return sorted(result,key=lambda x:(not x['active'],-x['signal']))

def connect_wifi(ssid,password):
    if not isinstance(ssid,str) or not 1<=len(ssid.encode())<=32 or '\x00' in ssid:raise ValueError('Invalid network name.')
    if not isinstance(password,str) or len(password)>128 or any(c in password for c in '\r\n\x00'):raise ValueError('Invalid network password.')
    progress('Connecting to Wi-Fi',.25)
    args=['nmcli','--wait','30','device','wifi','connect',ssid]
    if password:args+=['password',password]
    try:command(args,timeout=40)
    except Exception:raise ValueError('Could not connect. Check the Wi-Fi password and signal, then try again.') from None
    progress('Wi-Fi connected',1)

def audio():
    sinks=json.loads(user_command(['pactl','-f','json','list','sinks']))
    default=user_command(['pactl','get-default-sink']).strip()
    return [{'id':s['index'],'name':s['description'],'active':s['name']==default,'mute':s['mute'],'volume':int(next(iter(s['volume'].values()))['value_percent'].rstrip('%'))} for s in sinks]

def displays():
    text=user_command(['xrandr','--query']);result=[];current=None
    for line in text.splitlines():
        m=re.match(r'^(\S+) connected',line)
        if m:current={'name':m[1],'modes':[],'current':''};result.append(current)
        elif line and not line.startswith(' '):current=None
        elif current:
            m=re.match(r'^\s+(\d+x\d+)\s+(.*)',line)
            if m:
                if m[1] not in current['modes']:current['modes'].append(m[1])
                if '*' in m[2]:current['current']=m[1]
    return result

def set_display(output,mode):
    global DISPLAY_PENDING
    with DISPLAY_LOCK:
        if DISPLAY_PENDING:raise ValueError('Confirm or wait for the previous display change.')
        match=next((d for d in displays() if d['name']==output and mode in d['modes']),None)
        if not match:raise ValueError('That display mode is not available.')
        old=match['current'];user_command(['xrandr','--output',output,'--mode',mode])
        pending=(output,mode,old,time.monotonic()+20)
        DISPLAY_PENDING=pending
    def rollback():
        global DISPLAY_PENDING
        with DISPLAY_LOCK:
            if DISPLAY_PENDING==pending:
                target=DISPLAY_PENDING;DISPLAY_PENDING=None
                user_command(['xrandr','--output',target[0],'--mode',target[2]] if target[2] else ['xrandr','--output',target[0],'--auto'])
    threading.Timer(20,rollback).start()
    return {'confirm_seconds':20}

def confirm_display():
    global DISPLAY_PENDING
    with DISPLAY_LOCK:
        if not DISPLAY_PENDING:raise ValueError('Display change expired; the previous mode was restored.')
        output,mode,_,_=DISPLAY_PENDING;DISPLAY_PENDING=None
        user_command(['python3','-c',"import pathlib,sys;p=pathlib.Path.home()/'.config';p.mkdir(exist_ok=True);(p/'fgc-display.json').write_text(sys.argv[1])",json.dumps({'output':output,'mode':mode})])
    return {}

def update_system():
    if LIVE:raise ValueError('Install FGC before updating the system.')
    progress('Checking Ubuntu security and driver updates',.08)
    command(['apt-get','update'],timeout=600)
    progress('Installing system updates',.25)
    env=os.environ.copy();env['DEBIAN_FRONTEND']='noninteractive'
    p=subprocess.run(['apt-get','--with-new-pkgs','-y','-o','Dpkg::Options::=--force-confold','upgrade'],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=3600)
    if p.returncode:raise RuntimeError('System update failed. Restart and retry; USB repair keeps your games and saves. '+p.stdout[-500:])
    progress('Checking the FGC release',.70)
    request=urllib.request.Request('https://api.github.com/repos/spiderwisp/fgc-console/releases/latest',headers={'User-Agent':'FGC-OS','Accept':'application/vnd.github+json'})
    with urllib.request.urlopen(request,timeout=30) as response:release=json.load(response)
    tag=release['tag_name']
    if not re.fullmatch(r'v\d+\.\d+\.\d+',tag):raise ValueError('The release version is invalid.')
    current=Path('/opt/fgc/current').resolve().name
    if re.fullmatch(r'v\d+\.\d+\.\d+',current) and tuple(map(int,tag[1:].split('.')))<=tuple(map(int,current[1:].split('.'))):
        command(['update-grub'],timeout=120)
        progress('System updates checked. FGC is current. Restart to apply any driver updates.',1)
        return
    asset=next(a for a in release['assets'] if a['name']=='FGC-Console-Linux.tar.gz')
    digest=asset.get('digest','')
    if not re.fullmatch(r'sha256:[a-f0-9]{64}',digest) or not 0<int(asset['size'])<536870912:raise ValueError('Release verification metadata is missing.')
    url=asset['browser_download_url']
    if not url.startswith('https://github.com/spiderwisp/fgc-console/releases/download/'):raise ValueError('Invalid release URL.')
    with tempfile.TemporaryDirectory(prefix='fgc-update-') as temp:
        archive=Path(temp)/'console.tar.gz';total=0;sha=hashlib.sha256()
        with urllib.request.urlopen(url,timeout=90) as response,archive.open('wb') as out:
            while chunk:=response.read(1048576):
                total+=len(chunk)
                if total>asset['size']:raise ValueError('Release download is larger than expected.')
                sha.update(chunk);out.write(chunk)
        if total!=asset['size'] or 'sha256:'+sha.hexdigest()!=digest:raise ValueError('Release checksum did not match; FGC was not replaced.')
        with tarfile.open(archive) as tar:
            member=tar.getmember('FGC-Console-Linux/FGCConsole.x86_64')
            if not member.isfile() or member.size>536870912:raise ValueError('Invalid console executable.')
            payload=tar.extractfile(member).read()
            if not payload.startswith(b'\x7fELF'):raise ValueError('The console executable is not a Linux build.')
            system_files={}
            for name in ('system.py','fgcctl','seed.py','session.sh'):
                key='FGC-Console-Linux/system/'+name
                if key in tar.getnames():
                    item=tar.getmember(key)
                    if not item.isfile() or item.size>2097152:raise ValueError('Invalid console system component.')
                    system_files[name]=tar.extractfile(item).read()
        directory=Path('/opt/fgc/versions')/tag;directory.mkdir(parents=True,exist_ok=True)
        path=directory/'FGCConsole.x86_64';path.with_suffix('.new').write_bytes(payload);path.with_suffix('.new').chmod(0o755);os.replace(path.with_suffix('.new'),path)
        link=Path('/opt/fgc/current.new');link.unlink(missing_ok=True);link.symlink_to(directory);os.replace(link,'/opt/fgc/current')
        for name,body in system_files.items():
            path=Path('/usr/lib/fgc')/name;new=path.with_suffix(path.suffix+'.new');new.write_bytes(body);new.chmod(0o755);os.replace(new,path)
    command(['update-grub'],timeout=120)
    progress('Updates installed. Restart FGC to use them.',1)

def handle(req):
    action=req.get('action');args=req.get('args',{})
    if not isinstance(args,dict):raise ValueError('Invalid request.')
    if action=='status':
        with LOCK:job=JOB.copy()
        return {'live':LIVE,'version':json.loads(Path('/etc/fgc/os.json').read_text())['version'],'job':job,'network':command(['nmcli','-t','-f','STATE','general'],check=False).strip(),'storage_free':shutil.disk_usage('/home').free}
    if action=='disks':return {'disks':eligible_disks() if LIVE else []}
    if action=='install':
        if args.get('confirm')!='INSTALL FGC':raise ValueError('Confirm installation first.')
        selected_disk(args.get('token',''))
        return start_job(install,args['token'],args.get('repair') is True)
    if action=='networks':return {'networks':networks()}
    if action=='connect':return start_job(connect_wifi,args.get('ssid'),args.get('password',''))
    if action=='audio':return {'outputs':audio()}
    if action=='audio_set':
        sink=next((s for s in audio() if s['id']==args.get('id')),None)
        if not sink:raise ValueError('Audio output is unavailable.')
        volume=args.get('volume',70)
        if not isinstance(volume,int) or not 0<=volume<=100:raise ValueError('Invalid volume.')
        user_command(['pactl','set-default-sink',str(sink['id'])]);user_command(['pactl','set-sink-volume',str(sink['id']),str(volume)+'%']);user_command(['pactl','set-sink-mute',str(sink['id']),'1' if args.get('mute') is True else '0'])
        return {'outputs':audio()}
    if action=='displays':return {'displays':displays()}
    if action=='display_set':return set_display(args.get('output'),args.get('mode'))
    if action=='display_confirm':return confirm_display()
    if action=='update':return start_job(update_system)
    if action in ('shutdown','reboot'):
        if JOB['busy']:raise ValueError('Wait for the system operation to finish.')
        threading.Timer(1,lambda:command(['systemctl','poweroff' if action=='shutdown' else 'reboot'])).start();return {}
    raise ValueError('Unknown console operation.')

class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        try:
            _,uid,_=struct.unpack('3i',self.request.getsockopt(socket.SOL_SOCKET,socket.SO_PEERCRED,12))
            if uid not in (0,1000):raise PermissionError('Console account required.')
            raw=self.rfile.readline(16385)
            if len(raw)>16384:raise ValueError('Request is too large.')
            req=json.loads(raw)
            if not isinstance(req,dict):raise ValueError('Invalid request.')
            result={'ok':True,**handle(req)}
        except Exception as e:result={'ok':False,'error':str(e)}
        self.wfile.write(json.dumps(result).encode()+b'\n')

if __name__=='__main__':
    RUN.mkdir(exist_ok=True)
    path=RUN/'system.sock';path.unlink(missing_ok=True)
    with socketserver.ThreadingUnixStreamServer(str(path),Handler) as server:
        os.chown(path,0,1000);os.chmod(path,0o660);server.daemon_threads=True;server.serve_forever()
