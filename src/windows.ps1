param([Parameter(Mandatory=$true)][string]$RequestFile)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }
function Get-ReparseTag([string]$path) {
  if ($env:OS -ne 'Windows_NT') { throw "Symlinks and junctions are not supported: $path" }
  if (!('RelayPathInfo' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RelayPathInfo {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  struct FindData {
    public uint attributes;
    public System.Runtime.InteropServices.ComTypes.FILETIME created, accessed, written;
    public uint sizeHigh, sizeLow, tag, reserved;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string name;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=14)] public string alternate;
  }
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true, ExactSpelling=true)]
  static extern IntPtr FindFirstFileW(string path, out FindData data);
  [DllImport("kernel32.dll")]
  [return: MarshalAs(UnmanagedType.Bool)]
  static extern bool FindClose(IntPtr handle);
  public static uint Tag(string path) {
    FindData data;
    IntPtr handle=FindFirstFileW(path, out data);
    if (handle == new IntPtr(-1)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    try {
      if ((data.attributes & 0x400) == 0) throw new InvalidOperationException("Path attributes changed; retry the render.");
      return data.tag;
    } finally { FindClose(handle); }
  }
}
'@
  }
  return [RelayPathInfo]::Tag($path)
}
function Check-ReparseTag([uint32]$tag,[string]$path) {
  # A reparse point is not necessarily a link. Cloud Files tags describe sync
  # placeholders, while the name-surrogate bit means another path is targeted.
  # Allow only the documented CLOUD / CLOUD_1 .. CLOUD_F family, not arbitrary tags.
  if (($tag -band 0x20000000) -ne 0) { throw "Symlinks and junctions are not supported: $path" }
  if (($tag -band [uint32]4294905855) -ne [uint32]2415919130) {
    throw ('Unsupported Windows path marker 0x{0:X8} at {1}. Relay has not changed this file.' -f $tag,$path)
  }
}
function SafePath([string]$p) {
  if (![System.IO.Path]::IsPathRooted($p) -or $p.StartsWith('\\') -or $p.StartsWith('\\?\')) { throw 'Only local absolute Windows paths are supported.' }
  if ($p.Contains(';') -or $p.Substring(2).Contains(':')) { throw 'Semicolons and alternate data streams are not supported.' }
  $full=[IO.Path]::GetFullPath($p)
  $item=Get-Item -LiteralPath $full -Force
  if ($item.PSIsContainer) { throw 'Expected an existing file.' }
  $part=$item
  while ($null -ne $part) {
    if (($part.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      Check-ReparseTag (Get-ReparseTag $part.FullName) $part.FullName
    }
    $part=$part.Parent
    if ($null -eq $part -and $item -is [IO.FileInfo]) { $part=$item.Directory;$item=$part }
  }
  return $full
}
function HashStream($s) {
  $s.Position=0;$sha=[Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($s))).Replace('-','').ToLowerInvariant() }
  finally { $sha.Dispose();$s.Position=0 }
}
function WaveInfo($s) {
  # Conservative first release: standard RIFF WAV, PCM/IEEE float/extensible.
  # Reject incomplete files, RF64/BW64 and malformed chunk sizes instead of guessing.
  $s.Position=0;$r=[IO.BinaryReader]::new($s,[Text.Encoding]::ASCII,$true)
  try {
    if ($s.Length -lt 44) { throw 'WAV is empty or incomplete.' }
    $riff=[Text.Encoding]::ASCII.GetString($r.ReadBytes(4));$size=$r.ReadUInt32();$wave=[Text.Encoding]::ASCII.GetString($r.ReadBytes(4))
    if ($riff -ne 'RIFF' -or $wave -ne 'WAVE') { throw 'Expected a standard RIFF WAV (RF64/BW64 not yet supported).' }
    if ([int64]$size+8 -ne $s.Length) { throw 'WAV size does not match its header; render may be incomplete.' }
    $fmt=$false;$data=$false;$channels=0;$rate=0;$align=0;$bytes=0
    while ($s.Position+8 -le $s.Length) {
      $id=[Text.Encoding]::ASCII.GetString($r.ReadBytes(4));$length=$r.ReadUInt32();$end=$s.Position+[int64]$length
      if ($end -gt $s.Length) { throw 'WAV contains an incomplete chunk.' }
      if ($id -eq 'fmt ') {
        if ($length -lt 16) { throw 'WAV format chunk is incomplete.' }
        $tag=$r.ReadUInt16();$channels=$r.ReadUInt16();$rate=$r.ReadUInt32();$null=$r.ReadUInt32();$align=$r.ReadUInt16();$bits=$r.ReadUInt16()
        if ($tag -notin @(1,3,65534) -or $channels -lt 1 -or $channels -gt 64 -or $rate -lt 8000 -or $align -lt 1) { throw 'Unsupported WAV format.' }
        $fmt=$true
      }
      if ($id -eq 'data') { $bytes=$length;$data=$length -gt 0 }
      $s.Position=$end+($length % 2)
    }
    if (!$fmt -or !$data -or ($bytes % $align) -ne 0) { throw 'WAV contains no complete audio frames.' }
    return @{channels=$channels;rate=$rate}
  } finally { $r.Dispose();$s.Position=0 }
}
function AudioHash($s) {
  # Hash format and sample bytes, excluding render metadata such as BWF dates.
  $s.Position=12;$reader=[IO.BinaryReader]::new($s,[Text.Encoding]::ASCII,$true)
  $sha=[Security.Cryptography.SHA256]::Create();$buffer=New-Object byte[] 65536
  try {
    while ($s.Position+8 -le $s.Length) {
      $id=[Text.Encoding]::ASCII.GetString($reader.ReadBytes(4));$length=$reader.ReadUInt32();$end=$s.Position+[long]$length
      if ($end -gt $s.Length) { throw 'Incomplete WAV while hashing audio.' }
      if ($id -in @('fmt ','data')) {
        $remaining=[long]$length
        while ($remaining -gt 0) {
          $read=$s.Read($buffer,0,[int][Math]::Min($remaining,$buffer.Length))
          if (!$read) { throw 'Incomplete audio while hashing.' }
          $null=$sha.TransformBlock($buffer,0,$read,$buffer,0);$remaining-=$read
        }
      }
      $s.Position=$end+($length % 2)
    }
    $null=$sha.TransformFinalBlock([byte[]]@(),0,0)
    return ([BitConverter]::ToString($sha.Hash)).Replace('-','').ToLowerInvariant()
  } finally { $sha.Dispose();$reader.Dispose();$s.Position=0 }
}
function MediaHash($s) {
  $reader=[IO.BinaryReader]::new($s,[Text.Encoding]::ASCII,$true)
  try {
    if ($s.Length -lt 12 -or [Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -ne 'RIFF') { throw 'Converted media is not a RIFF WEM.' }
    $size=$reader.ReadUInt32()
    if ($size+8 -ne $s.Length -or [Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -ne 'WAVE') { throw 'Converted media is incomplete.' }
    $hash='';$hasData=$false
    while ($s.Position+8 -le $s.Length) {
      $id=[Text.Encoding]::ASCII.GetString($reader.ReadBytes(4));$length=$reader.ReadUInt32();$end=$s.Position+[long]$length
      if ($end -gt $s.Length) { throw 'Converted media contains an incomplete chunk.' }
      if ($id -eq 'hash' -and $length -eq 16) { $hash=([guid]::new($reader.ReadBytes(16))).ToString('B') }
      if ($id -eq 'data' -and $length -gt 0) { $hasData=$true }
      $s.Position=$end+($length % 2)
    }
    if (!$hash -or !$hasData) { throw 'Converted media has no content identity or audio data.' }
    return $hash
  } finally { $reader.Dispose();$s.Position=0 }
}
function Inspect([string]$p,[bool]$hash=$false) {
  try {
    $full=SafePath $p;$f=Get-Item -LiteralPath $full -Force
    $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
      $info=WaveInfo $stream
      $result=@{path=$p;ok=$true;stamp=([string]$f.LastWriteTimeUtc.Ticks+':'+[string]$f.Length);length=$f.Length;channels=$info.channels;rate=$info.rate}
      if ($hash) { $result.sha=HashStream $stream;$result.audioSha=AudioHash $stream }
      return $result
    } finally { $stream.Dispose() }
  } catch { return @{path=$p;ok=$false;error=$_.Exception.Message} }
}
function Invoke-Request($req) {
  Assert-RequestAlive
  if ($req.action -eq 'refresh') {
    return Refresh-ExistingSource $req
  } elseif ($req.action -eq 'waapi') {
    return Invoke-Waapi $req
  } elseif ($req.action -eq 'inspect') {
    $items=@(foreach ($p in $req.paths) { Inspect $p ([bool]$req.hash) })
    return @{ok=$true;items=$items}
  } elseif ($req.action -eq 'artifact') {
    $p=SafePath $req.path;$f=Get-Item -LiteralPath $p -Force
    $stream=[IO.File]::Open($p,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try { return @{ok=$true;length=$stream.Length;ticks=[string]$f.LastWriteTimeUtc.Ticks;contentHash=(MediaHash $stream)} }
    finally { $stream.Dispose() }
  } elseif ($req.action -eq 'replace') {
    $src=SafePath $req.source;$dst=SafePath $req.destination
    if ([StringComparer]::OrdinalIgnoreCase.Equals($src,$dst)) { throw 'Source and destination must differ.' }
    if (([IO.File]::GetAttributes($dst) -band [IO.FileAttributes]::ReadOnly) -ne 0) { throw 'Original WAV is read-only; check it out in source control first.' }
    $renderStream=$null;$original=$null;$out=$null;$temp=$null
    try {
      # No writer may change the render while it is validated and copied.
      $renderStream=[IO.File]::Open($src,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
      $si=Get-Item -LiteralPath $src -Force
      if (([string]$si.LastWriteTimeUtc.Ticks+':'+[string]$si.Length) -ne $req.stamp) { throw 'Render changed after it was queued.' }
      $wi=WaveInfo $renderStream;$sha=HashStream $renderStream
      $original=[IO.File]::Open($dst,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
      $old=WaveInfo $original;$oldAudioSha=AudioHash $original;$newAudioSha=AudioHash $renderStream
      if ($old.channels -ne $wi.channels) { throw 'Channel count changed; update skipped.' }
      if ((HashStream $original) -ne $req.destinationSha) { throw 'Wwise original changed while preparing this update; render again after the other edit finishes.' }
      $original.Dispose();$original=$null
      # Wwise may cache file identity at coarse timestamp resolution. Ensure a
      # distinct write time even when the same audio is rendered twice rapidly.
      $earliest=(Get-Item -LiteralPath $dst -Force).LastWriteTimeUtc.AddSeconds(2)
      if (($earliest-[DateTime]::UtcNow).TotalSeconds -gt 5) { throw 'Original WAV timestamp is in the future; correct it before retrying.' }
      while ([DateTime]::UtcNow -lt $earliest) { Assert-RequestAlive;Start-Sleep -Milliseconds 50 }
      $temp=Join-Path ([IO.Path]::GetDirectoryName($dst)) ('.wwise-relay-'+[guid]::NewGuid().ToString('N')+'.tmp')
      $out=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
      $renderStream.CopyTo($out);$out.Flush($true)
      if ((HashStream $out) -ne $sha) { throw 'Staged audio failed verification.' }
      $out.Dispose();$out=$null
      # Recheck immediately before the atomic, no-backup replacement.
      $original=[IO.File]::Open($dst,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
      if ((HashStream $original) -ne $req.destinationSha) { throw 'Original changed during replacement preparation.' }
      $original.Dispose();$original=$null
      Assert-RequestAlive
      [IO.File]::Replace($temp,$dst,[System.Management.Automation.Language.NullString]::Value);$temp=$null
      $verify=Inspect $dst $true
      if (!$verify.ok -or $verify.sha -ne $sha) { throw 'Replacement occurred, but readback verification failed. Check the original WAV.' }
      return @{ok=$true;sha=$sha;stamp=$verify.stamp;channels=$wi.channels;rate=$wi.rate;audioChanged=($oldAudioSha -ne $newAudioSha)}
    } finally {
      if ($null -ne $renderStream) {$renderStream.Dispose()};if ($null -ne $original) {$original.Dispose()};if ($null -ne $out) {$out.Dispose()}
      if ($null -ne $temp -and [IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
  } else { throw 'Unknown helper operation.' }
}

function Assert-RequestAlive {
  if ($script:serviceDir) {
    $heartbeat=Get-Item -LiteralPath (Join-Path $script:serviceDir 'heartbeat') -ErrorAction SilentlyContinue
    if ((Test-Path -LiteralPath (Join-Path $script:serviceDir 'stop')) -or
        [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -gt $script:expires -or !$heartbeat -or
        ([DateTime]::UtcNow-$heartbeat.LastWriteTimeUtc).TotalSeconds -gt 8) {
      throw 'Request stopped, REAPER stopped responding, or the operation timed out before committing changes.'
    }
  }
}
function Send-Wamp([string]$json,$token) {
  $bytes=[Text.Encoding]::UTF8.GetBytes($json)
  $segment=[ArraySegment[byte]]::new($bytes)
  $null=$script:socket.SendAsync($segment,[Net.WebSockets.WebSocketMessageType]::Text,$true,$token).GetAwaiter().GetResult()
}
function Receive-Wamp($token) {
  $buffer=New-Object byte[] 16384;$segment=[ArraySegment[byte]]::new($buffer)
  $stream=[IO.MemoryStream]::new()
  try {
    do {
      $part=$script:socket.ReceiveAsync($segment,$token).GetAwaiter().GetResult()
      if ($part.MessageType -ne [Net.WebSockets.WebSocketMessageType]::Text) { throw 'Wwise closed the connection or returned a non-text response.' }
      $stream.Write($buffer,0,$part.Count)
      if ($stream.Length -gt 33554432) { throw 'Wwise response exceeded the 32 MB limit; updates paused.' }
    } while (!$part.EndOfMessage)
    $message=[Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
    return ,$message
  } finally { $stream.Dispose() }
}
function Invoke-Waapi($req,[switch]$ExistingSourceRefresh) {
  $allowed=@('ak.wwise.core.object.get','ak.wwise.core.getInfo','ak.wwise.core.getProjectInfo',
    'ak.wwise.core.audio.convert','ak.wwise.ui.commands.execute','ak.wwise.ui.bringToForeground')
  if ($ExistingSourceRefresh) { $allowed+='ak.wwise.core.audio.import' }
  if ($req.uri -notin $allowed) { throw 'Wwise operation is not permitted.' }
  if ($req.uri -eq 'ak.wwise.ui.commands.execute' -and $req.args.command -ne 'FindInProjectExplorerSyncGroup1') { throw 'Only navigation is permitted.' }
  if ($req.uri -eq 'ak.wwise.core.audio.convert' -and
      (@($req.args.objects).Count -ne 1 -or [string]$req.args.objects[0] -notmatch '^\{[0-9a-fA-F-]{36}\}$' -or
       @($req.args.platforms).Count -ne 1 -or @($req.args.languages).Count -ne 1 -or $req.args.languages[0] -ne 'SFX')) { throw 'Invalid conversion scope.' }
  $port=[int]$req.port
  if ($port -lt 1 -or $port -gt 65535) { throw 'Invalid WAAPI port.' }
  $ms=15000
  if ($req.uri -eq 'ak.wwise.core.object.get' -and $req.args.waql) { $ms=60000 }
  if ($req.uri -in @('ak.wwise.core.audio.convert','ak.wwise.core.audio.import')) { $ms=120000 }
  $cancel=[Threading.CancellationTokenSource]::new($ms)
  try {
    if (!$script:socket -or $script:socket.State -ne [Net.WebSockets.WebSocketState]::Open -or $script:socketPort -ne $port) {
      if ($script:socket) { $script:socket.Dispose() }
      $script:socket=[Net.WebSockets.ClientWebSocket]::new()
      $script:socket.Options.AddSubProtocol('wamp.2.json');$script:socket.Options.Proxy=$null
      $null=$script:socket.ConnectAsync([uri]('ws://127.0.0.1:'+ $port +'/waapi'),$cancel.Token).GetAwaiter().GetResult()
      Send-Wamp '[1,"realm1",{"roles":{"caller":{}}}]' $cancel.Token
      $welcome=Receive-Wamp $cancel.Token
      if ($welcome[0] -ne 2) { throw 'Wwise did not accept the WAAPI session.' }
      $script:socketPort=$port
    }
    Assert-RequestAlive
    $script:callId++;$id=$script:callId
    $options=$req.options | ConvertTo-Json -Depth 50 -Compress
    $arguments=$req.args | ConvertTo-Json -Depth 50 -Compress
    $uriJson=$req.uri | ConvertTo-Json -Compress
    Send-Wamp ('[48,'+$id+','+$options+','+$uriJson+',[],'+$arguments+']') $cancel.Token
    $message=Receive-Wamp $cancel.Token
    if ($message[0] -eq 8) {
      $why=[string]$message[4];if ($message.Count -gt 6 -and $message[6].message) { $why=[string]$message[6].message }
      throw ('Wwise: '+$why)
    }
    if ($message[0] -ne 50 -or $message[1] -ne $id -or $message.Count -lt 5) { throw 'Unexpected Wwise response.' }
    return @{ok=$true;data=$message[4]}
  } catch {
    if ($script:socket) { $script:socket.Abort();$script:socket.Dispose();$script:socket=$null }
    if ($cancel.IsCancellationRequested) {
      $operation=[string]$req.operation;if (!$operation) { $operation=[string]$req.uri }
      $detail='This read request does not change audio.'
      if ($req.uri -eq 'ak.wwise.core.audio.convert') { $detail='The requested conversion may still finish in Wwise.' }
      elseif ($req.uri -eq 'ak.wwise.core.audio.import') { $detail='The existing-source refresh may still finish in Wwise.' }
      elseif ($req.uri -like 'ak.wwise.ui.*') { $detail='Wwise navigation did not respond.' }
      throw ($operation+' timed out after '+($ms/1000)+' seconds. '+$detail+' Updates are paused.')
    }
    throw
  } finally { $cancel.Dispose() }
}
function Refresh-ExistingSource($req) {
  $read=@{port=$req.port;uri='ak.wwise.core.object.get';operation='Verify existing source before refresh'}
  $read.args=@{from=@{ofType=@('Project')}};$read.options=@{return=@('id','filePath')}
  $project=@((Invoke-Waapi $read).data.return)
  if ($project.Count -ne 1 -or $project[0].id -ne $req.projectId -or $project[0].filePath -ne $req.projectPath) { throw 'Wrong Wwise project before source refresh.' }
  if ([string]$req.sourceId -notmatch '^\{[0-9a-fA-F-]{36}\}$') { throw 'Invalid source identity.' }
  $read.args=@{from=@{id=@($req.sourceId)}};$read.options=@{return=@('id','type','parent','originalWavFilePath')}
  $sources=@((Invoke-Waapi $read).data.return)
  if ($sources.Count -ne 1 -or $sources[0].type -ne 'AudioFileSource' -or $sources[0].parent.id -ne $req.soundId -or $sources[0].originalWavFilePath -ne $req.original) { throw 'Existing source identity changed before refresh.' }
  $read.args=@{from=@{id=@($req.soundId)}};$read.options=@{return=@('activeSource');platform=$req.platform}
  $sounds=@((Invoke-Waapi $read).data.return)
  if ($sounds.Count -ne 1 -or $sounds[0].activeSource.id -ne $req.sourceId) { throw 'Active audio source changed before refresh.' }
  $info=Invoke-Waapi @{port=$req.port;uri='ak.wwise.core.getProjectInfo';args=@{};options=@{};operation='Verify SFX directory'}
  $prefix=([string]$info.data.directories.originals).TrimEnd('\')+'\SFX\'
  if (![string]$req.original -or !([string]$req.original).StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or [string]$req.original -match '["\x00-\x1f]') { throw 'Only existing SFX originals may be refreshed.' }
  $read.args=@{waql=('from type AudioFileSource where originalWavFilePath = "'+$req.original+'"')};$read.options=@{return=@('id')}
  $owners=@((Invoke-Waapi $read).data.return)
  if ($owners.Count -ne 1 -or $owners[0].id -ne $req.sourceId) { throw 'Shared originals cannot be refreshed.' }
  # Only this existing source GUID and its own existing file are supplied. No
  # Sound paths, object types, new filenames, properties or creation options.
  $relative=([string]$req.original).Substring($prefix.Length)
  $separator=$relative.LastIndexOf('\');$subfolder=''
  if ($separator -ge 0) { $subfolder=$relative.Substring(0,$separator) }
  if ($relative.Split('\') -contains '..' -or $relative.Split('\') -contains '.') { throw 'Original path is not canonical.' }
  $importArgs=@{importOperation='useExisting';default=@{importLanguage='SFX';importLocation=$req.sourceId;originalsSubFolder=$subfolder};imports=@(@{audioFile=$req.original;objectPath=''})}
  $call=@{port=$req.port;uri='ak.wwise.core.audio.import';args=$importArgs;options=@{};operation='Refresh the existing Wwise source'}
  $result=(Invoke-Waapi $call -ExistingSourceRefresh).data
  if (@($result.log).Count -ne 0) { throw ('Source refresh: '+(($result.log | ForEach-Object {$_.message}) -join '; ')) }
  if (@($result.objects).Count -ne 1 -or $result.objects[0].id -ne $req.sourceId -or @($result.files).Count -ne 1 -or $result.files[0] -ne $req.original) { throw 'Wwise did not confirm the exact existing source refresh.' }
  return @{ok=$true}
}
function Service([string]$directory) {
  $script:serviceDir=[IO.Path]::GetFullPath($directory)
  $dir=$script:serviceDir;$stop=Join-Path $dir 'stop';$inbox=Join-Path $dir 'inbox.json'
  $reason='Background helper stopped. Connect to Wwise again.'
  try {
    [IO.File]::WriteAllText((Join-Path $dir 'ready'),'ready')
    while (!(Test-Path -LiteralPath $stop)) {
      $heartbeat=Get-Item -LiteralPath (Join-Path $dir 'heartbeat') -ErrorAction SilentlyContinue
      if (!$heartbeat -or ([DateTime]::UtcNow-$heartbeat.LastWriteTimeUtc).TotalMinutes -gt 30) { break }
      if (Test-Path -LiteralPath $inbox) {
        $message=[IO.File]::ReadAllText($inbox,[Text.Encoding]::UTF8) | ConvertFrom-Json
        if ([string]$message.id -notmatch '^[0-9]+$' -or !$message.request -or !$message.expires) { throw 'Invalid background request.' }
        [IO.File]::Delete($inbox);$script:expires=[long]$message.expires
        try { $answer=Invoke-Request $message.request } catch { $answer=@{ok=$false;error=$_.Exception.Message} }
        $json=$answer | ConvertTo-Json -Depth 50 -Compress
        $temp=Join-Path $dir ('response-'+$message.id+'.tmp');$dest=Join-Path $dir ('response-'+$message.id+'.json')
        [IO.File]::WriteAllText($temp,$json,[Text.UTF8Encoding]::new($false));[IO.File]::Move($temp,$dest)
      }
      Start-Sleep -Milliseconds 40
    }
  } catch { $reason=$_.Exception.Message }
  finally {
    if ($script:socket) { $script:socket.Abort();$script:socket.Dispose();$script:socket=$null }
    [IO.File]::WriteAllText((Join-Path $dir 'stopped.json'),(@{error=$reason}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    $script:serviceDir=$null
  }
}
try {
  $req=Get-Content -LiteralPath $RequestFile -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($req.action -eq 'service') { Service $req.directory }
  else { Invoke-Request $req | ConvertTo-Json -Depth 50 -Compress }
} catch { @{ok=$false;error=$_.Exception.Message} | ConvertTo-Json -Compress }
