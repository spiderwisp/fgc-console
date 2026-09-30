#!/usr/bin/env python3
"""Validate the reviewed catalog and its GitHub release metadata."""
import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def require(condition, message):
    if not condition:
        raise ValueError(message)

def text(value, pattern):
    return isinstance(value, str) and re.fullmatch(pattern, value) is not None

def safe_path(value):
    if not isinstance(value, str) or not 1 <= len(value) <= 240 or not value.isascii():
        return False
    if any(c in value for c in '\\:*?"<>|') or value.startswith('/'):
        return False
    for part in value.rstrip('/').split('/'):
        if not part or part in ('.', '..') or part.endswith(('.', ' ')):
            return False
        if part.split('.')[0].upper() in {'CON','PRN','AUX','NUL', *('COM'+str(i) for i in range(1,10)), *('LPT'+str(i) for i in range(1,10))}:
            return False
    return True

def github(path):
    headers={'Accept':'application/vnd.github+json', 'User-Agent':'fgc-catalog-validator'}
    token=os.environ.get('GITHUB_TOKEN')
    if token:
        headers['Authorization']='Bearer '+token
    request=urllib.request.Request('https://api.github.com/repos/'+path, headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)

def validate(path, online=False):
    data=json.loads(path.read_text(encoding='utf-8'))
    require(data.get('schema_version') == 1, 'schema_version must be 1')
    games=data.get('games')
    require(isinstance(games,list) and len(games)<=500, 'games must contain at most 500 entries')
    ids=set(); repos=set()
    for game in games:
        require(isinstance(game,dict), 'Each entry must be an object')
        gid=game.get('id')
        require(text(gid,r'[a-z0-9][a-z0-9-]{1,63}') and gid not in ids, 'Invalid or duplicate game ID')
        ids.add(gid)
        repo=game.get('repo')
        require(text(repo,r'[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}'), gid+': invalid repository')
        require(repo.lower() not in repos, gid+': repository already listed')
        repos.add(repo.lower())
        for field in ('title','description','license','version'):
            value=game.get(field)
            require(isinstance(value,str) and 1<=len(value)<=(500 if field=='description' else 80), gid+': invalid '+field)
        require(text(game.get('release'),r'[A-Za-z0-9][A-Za-z0-9_.-]{0,79}'),gid+': invalid release tag')
        require(game.get('gamepad') is True,gid+': controller support is required')
        require(isinstance(game.get('tags'),list) and len(game['tags'])<=8 and all(isinstance(v,str) and 1<=len(v)<=24 for v in game['tags']),gid+': invalid tags')
        require(game.get('cover')=='catalog/artwork/'+gid+'.jpg',gid+': cover must match the game ID')
        cover=ROOT/game['cover']
        require(cover.is_file() and cover.stat().st_size<=2097152,gid+': add a JPEG cover under 2 MiB')
        require(cover.read_bytes()[:2]==b'\xff\xd8',gid+': cover is not JPEG')
        builds=game.get('platforms')
        require(isinstance(builds,dict) and 'linux-x86_64' in builds,gid+': Linux x86_64 is required')
        release=None
        if online:
            project=github(repo)
            require(not project.get('private') and not project.get('archived'),gid+': repository must be public and active')
            require(project.get('license') and project['license'].get('spdx_id')==game['license'],gid+': repository license must match the catalog SPDX identifier')
            release=github(repo+'/releases/tags/'+game['release'])
            require(not release.get('draft'),gid+': release must be published')
        for platform,build in builds.items():
            prefix=gid+'/'+platform+': '
            require(platform in ('linux-x86_64','windows-x86_64'),prefix+'unsupported platform')
            require(isinstance(build,dict),prefix+'build must be an object')
            require(text(build.get('asset'),r'[A-Za-z0-9][A-Za-z0-9_.-]{0,119}\.zip'),prefix+'asset must be a ZIP filename')
            require(text(build.get('sha256'),r'[a-f0-9]{64}'),prefix+'SHA-256 is required')
            require(type(build.get('size')) is int and 1<=build['size']<=536870912,prefix+'size must be 1 byte to 512 MiB')
            require(safe_path(build.get('executable')) and not build['executable'].endswith('/'),prefix+'unsafe executable path')
            args=build.get('args',[])
            require(isinstance(args,list) and len(args)<=16 and all(isinstance(a,str) and len(a)<=256 and not any(c in a for c in '\r\n\0') for a in args),prefix+'invalid arguments')
            require(build.get('session_protocol','') in ('','fgc-v1'),prefix+'unknown session protocol')
            if release:
                assets=[a for a in release.get('assets',[]) if a['name']==build['asset']]
                require(len(assets)==1,prefix+'asset missing from release')
                asset=assets[0]
                require(asset['size']==build['size'],prefix+'release size differs')
                require(asset.get('digest')=='sha256:'+build['sha256'],prefix+'release checksum differs')
        print('Valid:',repo,game['release'])
    print(f'{len(games)} approved catalog entries validated.')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--online',action='store_true')
    parser.add_argument('catalog',nargs='?',type=Path,default=ROOT/'catalog/games.json')
    args=parser.parse_args()
    try:
        validate(args.catalog,args.online)
    except (ValueError,KeyError,TypeError,OSError,urllib.error.URLError) as error:
        print('Catalog rejected:',error,file=sys.stderr)
        sys.exit(1)
