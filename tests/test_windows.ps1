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
function Wem([string]$p) {
  Wave $p 22
  $bytes=[IO.File]::ReadAllBytes($p);$stream=[IO.MemoryStream]::new();$writer=[IO.BinaryWriter]::new($stream)
  try {
    $writer.Write($bytes);$writer.Write([Text.Encoding]::ASCII.GetBytes('hash'));$writer.Write([uint32]16)
    $writer.Write(([guid]'{11111111-2222-3333-4444-555555555555}').ToByteArray())
    $stream.Position=4;$writer.Write([uint32]($stream.Length-8));[IO.File]::WriteAllBytes($p,$stream.ToArray())
  } finally {$writer.Dispose();$stream.Dispose()}
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
  Check ($out.ok -and $out.audioChanged -and (Sha $src) -eq (Sha $dst)) 'Exact bytes replace the existing original'
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
  Check (!$out.ok) 'An ordinary WAV without Wwise content identity is rejected'
  $cache=Join-Path $root 'converted.wem';Wem $cache
  $out=Call @{action='artifact';path=$cache}
  Check ($out.ok -and $out.contentHash -eq '{11111111-2222-3333-4444-555555555555}') 'Converted WEM content identity is read from its hash chunk'
  $same=Call @{action='inspect';paths=@($dst);hash=$true}
  $out=Call @{action='replace';source=$dst;destination=$src;stamp=$same.items[0].stamp;destinationSha=(Sha $src)}
  Check ($out.ok -and $out.audioChanged) 'Audio sample changes are distinguished from metadata'
  $same=Call @{action='inspect';paths=@($dst);hash=$true}
  $out=Call @{action='replace';source=$dst;destination=$src;stamp=$same.items[0].stamp;destinationSha=(Sha $src)}
  Check ($out.ok -and !$out.audioChanged) 'Identical audio is detected on a repeated replacement'

  $plain=Call @{action='inspect';paths=@($src);hash=$true}
  $bytes=[IO.File]::ReadAllBytes($src);$stream=[IO.MemoryStream]::new();$writer=[IO.BinaryWriter]::new($stream)
  try {
    $writer.Write($bytes);$writer.Write([Text.Encoding]::ASCII.GetBytes('JUNK'));$writer.Write([uint32]4);$writer.Write([uint32]123)
    $stream.Position=4;$writer.Write([uint32]($stream.Length-8));[IO.File]::WriteAllBytes($src,$stream.ToArray())
  } finally {$writer.Dispose();$stream.Dispose()}
  $metadata=Call @{action='inspect';paths=@($src);hash=$true}
  Check ($metadata.items[0].sha -ne $plain.items[0].sha -and $metadata.items[0].audioSha -eq $plain.items[0].audioSha) 'Render metadata changes do not require a new audio-content hash'
  $hidden=Join-Path $root '.cached.wem';Wem $hidden
  [IO.File]::SetLastWriteTimeUtc($hidden,[datetime]::UtcNow.AddYears(-1))
  if ($env:OS -eq 'Windows_NT') { [IO.File]::SetAttributes($hidden,[IO.FileAttributes]::Hidden) }
  $out=Call @{action='artifact';path=$hidden}
  Check ($out.ok -and $out.length -gt 0) 'A readable hidden converted cache is accepted regardless of age'
  $locked=[IO.File]::Open($hidden,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try {$out=Call @{action='artifact';path=$hidden};Check (!$out.ok) 'Converted media held by a writer is rejected'} finally {$locked.Dispose()}
  $out=Call @{action='artifact';path=(Join-Path $root 'missing.wem')}
  Check (!$out.ok) 'Missing converted media is rejected'
  $unicode=Join-Path $root '火.wav';Wave $unicode 12;$a=Call @{action='inspect';paths=@($unicode)}
  Check ($a.items[0].ok) 'Unicode filenames work'
  # Test the production tag classifier without needing a Dropbox account/provider.
  $ast=[System.Management.Automation.Language.Parser]::ParseFile($worker,[ref]$null,[ref]$null)
  foreach ($name in @('Check-ReparseTag','Get-ReparseTag')) {
    $fn=$ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    . ([scriptblock]::Create($fn.Extent.Text))
  }
  foreach ($variant in 0..15) { Check-ReparseTag ([uint32](2415919130 + $variant*4096)) 'cloud folder' }
  Check $true 'All documented Windows Cloud Files tag variants are allowed'
  foreach ($tag in @([uint32]2684354563,[uint32]2684354572,[uint32]2684354589,[uint32]2147483649,[uint32]0)) {
    $rejected=$false
    try { Check-ReparseTag $tag 'exact component' } catch { $rejected=$_.Exception.Message.Contains('exact component') }
    Check $rejected ('Redirecting or unknown tag 0x{0:X8} is rejected with its location' -f $tag)
  }
  if ($env:OS -eq 'Windows_NT') {
    $target=Join-Path $root 'target';[IO.Directory]::CreateDirectory($target) | Out-Null
    $targetWav=Join-Path $target 'audio.wav';Wave $targetWav 15;$originalHash=Sha $targetWav
    $junction=Join-Path $root 'junction'
    New-Item -ItemType Junction -Path $junction -Target $target | Out-Null
    try {
      Check ((Get-ReparseTag $junction) -eq [uint32]2684354563) 'Native Windows tag lookup identifies a real junction'
      $viaLink=Join-Path $junction 'audio.wav'
      $a=Call @{action='inspect';paths=@($viaLink)}
      Check (!$a.items[0].ok -and $a.items[0].error.Contains($junction)) 'Render through a junction is rejected and identifies the parent'
      Wave $src 18;$a=Call @{action='inspect';paths=@($src)}
      $out=Call @{action='replace';source=$src;destination=$viaLink;stamp=$a.items[0].stamp;destinationSha=$originalHash}
      Check (!$out.ok -and (Sha $targetWav) -eq $originalHash) 'Original through a junction is rejected without modifying target audio'
    } finally { [IO.Directory]::Delete($junction) }
  }
  Write-Host "Passed $count Windows file-safety tests."
} finally {
  # This entire directory is owned by this test and contains synthetic audio only.
  Get-ChildItem $root -File | ForEach-Object {$_.Attributes=[IO.FileAttributes]::Normal}
  Remove-Item -LiteralPath $root -Recurse -Force
}
