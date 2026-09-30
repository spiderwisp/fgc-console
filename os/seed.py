#!/usr/bin/python3
import json, os, re, shutil
from pathlib import Path

seed=Path('/usr/share/fgc/seed')
user=Path('/home/fgc/.local/share/FGC Console')
user.mkdir(parents=True,exist_ok=True)
record=user/'installed.json'
try: installed=json.loads(record.read_text())
except (OSError,ValueError): installed={}
if not isinstance(installed,dict):installed={}
manifest=json.loads((seed/'installed.json').read_text())
for game,entry in manifest.items():
    current=installed.get(game,{})
    if isinstance(current,dict) and re.fullmatch('[a-f0-9]{64}',str(current.get('sha256',''))):
        executable=Path(str(current.get('executable','')))
        if not executable.is_absolute() and '..' not in executable.parts and (user/'games'/game/current['sha256']/executable).is_file():continue
    source=seed/'games'/game/entry['sha256']
    target=user/'games'/game/entry['sha256']
    staging=target.parent/'.seed-staging'
    if staging.exists():shutil.rmtree(staging)
    shutil.copytree(source,staging)
    if target.is_symlink():target.unlink()
    elif target.exists():shutil.rmtree(target)
    staging.rename(target)
    installed[game]=entry
record.with_suffix('.tmp').write_text(json.dumps(installed))
os.replace(record.with_suffix('.tmp'),record)
