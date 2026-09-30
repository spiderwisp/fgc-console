param([string]$ConsoleBinary,[string]$GameZip,[string]$Output)
$ErrorActionPreference='Stop'
$sourceRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if(-not $ConsoleBinary -or -not $GameZip -or -not $Output){throw 'Supply -ConsoleBinary, -GameZip and -Output.'}
$binary=(Resolve-Path $ConsoleBinary).Path
$game=(Resolve-Path $GameZip).Path
New-Item -ItemType Directory -Force $Output | Out-Null
$destination=(Resolve-Path $Output).Path
docker build -t fgc-os-builder:0.2.0 $PSScriptRoot
if($LASTEXITCODE -ne 0){throw 'Ubuntu image build failed'}
docker volume create fgc-os-build | Out-Null
docker run --rm --cap-add SYS_ADMIN --security-opt apparmor=unconfined --mount 'type=volume,source=fgc-os-build,target=/build' --mount "type=bind,source=$sourceRoot,target=/src,readonly" --mount "type=bind,source=$binary,target=/artifacts/FGCConsole.x86_64,readonly" --mount "type=bind,source=$game,target=/artifacts/DeepSignal-Linux.zip,readonly" --mount "type=bind,source=$destination,target=/out" fgc-os-builder:0.2.0 python3 /src/os/assemble.py
if($LASTEXITCODE -ne 0){throw 'FGC ISO assembly failed'}
