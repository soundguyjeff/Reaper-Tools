$ErrorActionPreference='Stop'
$worker=Join-Path $PSScriptRoot '../src/windows.ps1'
$root=Join-Path ([IO.Path]::GetTempPath()) ('WwiseRelayTests-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$count=0
function Wave([string]$p,[int]$seed=0,[int]$channels=1) {
  $f=[IO.File]::Open($p,[IO.FileMode]::Create);$w=[IO.BinaryWriter]::new($f)
  try {
    $len=480*$channels*2
    $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF'));$w.Write([uint32](36+$len));$w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $w.Write([uint32]16);$w.Write([uint16]1);$w.Write([uint16]$channels);$w.Write([uint32]48000);$w.Write([uint32](96000*$channels));$w.Write([uint16](2*$channels));$w.Write([uint16]16)
    $w.Write([Text.Encoding]::ASCII.GetBytes('data'));$w.Write([uint32]$len)
    for($i=0;$i -lt 480*$channels;$i++) {$w.Write([int16](($i+$seed)%30000))}
  } finally {$w.Dispose();$f.Dispose()}
}
function Call($obj) {
  $request=Join-Path $root 'request.json'
  [IO.File]::WriteAllText($request,($obj | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
  return (& $worker -RequestFile $request | ConvertFrom-Json)
}
function Check([bool]$condition,[string]$name) { if(!$condition){throw "FAILED: $name"};$script:count++;Write-Host "PASS $name" }
function Sha([string]$p) {return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
try {
  $src=Join-Path $root "render's `$file.wav";$dst=Join-Path $root 'existing.wav';$other=Join-Path $root 'unrelated.wav'
  Wave $src 25;Wave $dst 1;Wave $other 9;$oldOther=Sha $other
  $a=Call @{action='inspect';paths=@($src,$dst);hash=$true}
  Check ($a.ok -and $a.items.Count -eq 2 -and $a.items[0].ok) 'Valid PCM WAVs can be inspected'
  $request=@{action='replace';source=$src;destination=$dst;stamp=$a.items[0].stamp;destinationSha=$a.items[1].sha}
  $out=Call $request
  Check ($out.ok -and (Sha $src) -eq (Sha $dst)) 'Exact bytes replace the existing original'
  Check ((Sha $other) -eq $oldOther) 'Unrelated WAV remains unchanged'
  Check (@(Get-ChildItem $root -Filter '*.tmp').Count -eq 0) 'Successful staging leaves no temporary audio'
  Check (@(Get-ChildItem $root -Filter '*.bak').Count -eq 0) 'No WAV backup is created'
  $again=Call $request
  Check (!$again.ok) 'Destination conflict is rejected'
  $missing=Join-Path $root 'new.wav';$request.destination=$missing
  $out=Call $request
  Check (!$out.ok -and !(Test-Path $missing)) 'Missing destination is never created'
  $request.destination=$dst;$request.destinationSha=Sha $dst
  $request.stamp='old';$before=Sha $dst;$out=Call $request
  Check (!$out.ok -and (Sha $dst) -eq $before) 'Render changed since queueing is rejected'
  $request.stamp=$a.items[0].stamp
  [IO.File]::SetAttributes($dst,[IO.FileAttributes]::ReadOnly)
  $out=Call $request
  Check (!$out.ok -and (Sha $dst) -eq $before) 'Read-only original is never forced writable'
  [IO.File]::SetAttributes($dst,[IO.FileAttributes]::Normal)
  Wave $src 10 2;$a=Call @{action='inspect';paths=@($src);hash=$true};$request.stamp=$a.items[0].stamp
  $out=Call $request
  Check (!$out.ok -and (Sha $dst) -eq $before) 'Channel changes cannot replace the original'
  [IO.File]::WriteAllBytes($src,[byte[]](1,2,3));$a=Call @{action='inspect';paths=@($src);hash=$true}
  Check (!$a.items[0].ok) 'Truncated WAV is rejected'
  Wave $src 10;$bytes=[IO.File]::ReadAllBytes($src);$bytes[4]=1;[IO.File]::WriteAllBytes($src,$bytes)
  $a=Call @{action='inspect';paths=@($src)}
  Check (!$a.items[0].ok) 'Incorrect RIFF size is rejected'
  Wave $src 11;$locked=[IO.File]::Open($src,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try {$a=Call @{action='inspect';paths=@($src)};Check (!$a.items[0].ok) 'A file still held by a writer is skipped'} finally {$locked.Dispose()}
  $a=Call @{action='inspect';paths=@($src)};$request.stamp=$a.items[0].stamp;$request.destination=$src
  $out=Call $request
  Check (!$out.ok) 'Source equal to destination is rejected'
  $out=Call @{action='artifact';path=$dst}
  Check ($out.ok -and $out.length -gt 0 -and $out.ticks) 'Converted-artifact metadata can be read'
  $unicode=Join-Path $root '火.wav';Wave $unicode 12;$a=Call @{action='inspect';paths=@($unicode)}
  Check ($a.items[0].ok) 'Unicode filenames work'
  Write-Host "Passed $count Windows file-safety tests."
} finally {
  # This entire directory is owned by this test and contains synthetic audio only.
  Get-ChildItem $root -File | ForEach-Object {$_.Attributes=[IO.FileAttributes]::Normal}
  Remove-Item -LiteralPath $root -Recurse -Force
}
