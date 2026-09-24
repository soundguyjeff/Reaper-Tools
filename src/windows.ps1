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
function Inspect([string]$p,[bool]$hash=$false) {
  try {
    $full=SafePath $p;$f=Get-Item -LiteralPath $full
    $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
      $info=WaveInfo $stream
      $result=@{path=$p;ok=$true;stamp=([string]$f.LastWriteTimeUtc.Ticks+':'+[string]$f.Length);length=$f.Length;channels=$info.channels;rate=$info.rate}
      if ($hash) { $result.sha=HashStream $stream }
      return $result
    } finally { $stream.Dispose() }
  } catch { return @{path=$p;ok=$false;error=$_.Exception.Message} }
}
function Monitor([string]$directory) {
  $dir=[IO.Path]::GetFullPath($directory)
  if (!(Test-Path -LiteralPath $dir -PathType Container)) { throw 'Missing file-check session directory.' }
  $inbox=Join-Path $dir 'inbox.json';$stop=Join-Path $dir 'stop'
  $reason='File inspector stopped after being idle; a new session will start on the next check.'
  try {
    [IO.File]::WriteAllText((Join-Path $dir 'ready'),'ready')
    $idle=[DateTime]::UtcNow
    while (!(Test-Path -LiteralPath $stop) -and ([DateTime]::UtcNow-$idle).TotalSeconds -lt 30) {
      if (Test-Path -LiteralPath $inbox) {
        $message=[IO.File]::ReadAllText($inbox,[Text.Encoding]::UTF8) | ConvertFrom-Json
        if ([string]$message.id -notmatch '^[0-9]+$' -or !$message.paths -or $message.action) { throw 'Invalid read-only inspection request.' }
        [IO.File]::Delete($inbox)
        # Only inspect is available in the persistent worker. It cannot replace audio.
        $items=@(foreach ($path in $message.paths) { Inspect $path $false })
        $json=@{ok=$true;items=$items} | ConvertTo-Json -Depth 8 -Compress
        $temp=Join-Path $dir ('response-'+$message.id+'.tmp')
        $dest=Join-Path $dir ('response-'+$message.id+'.json')
        [IO.File]::WriteAllText($temp,$json,[Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temp,$dest) # Publish a complete, unique response atomically.
        $idle=[DateTime]::UtcNow
      }
      Start-Sleep -Milliseconds 100
    }
  } catch { $reason=$_.Exception.Message }
  finally {
    $json=@{error=$reason} | ConvertTo-Json -Compress
    [IO.File]::WriteAllText((Join-Path $dir 'stopped.json'),$json,[Text.UTF8Encoding]::new($false))
  }
}

try {
  $req=Get-Content -LiteralPath $RequestFile -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($req.action -eq 'monitor') {
    Monitor $req.directory
  } elseif ($req.action -eq 'inspect') {
    $items=@(foreach ($p in $req.paths) { Inspect $p ([bool]$req.hash) })
    @{ok=$true;items=$items} | ConvertTo-Json -Depth 8 -Compress
  } elseif ($req.action -eq 'artifact') {
    $p=SafePath $req.path;$f=Get-Item -LiteralPath $p
    @{ok=$true;length=$f.Length;ticks=[string]$f.LastWriteTimeUtc.Ticks} | ConvertTo-Json -Compress
  } elseif ($req.action -eq 'replace') {
    $src=SafePath $req.source;$dst=SafePath $req.destination
    if ([StringComparer]::OrdinalIgnoreCase.Equals($src,$dst)) { throw 'Source and destination must differ.' }
    if (([IO.File]::GetAttributes($dst) -band [IO.FileAttributes]::ReadOnly) -ne 0) { throw 'Original WAV is read-only; check it out in source control first.' }
    $renderStream=$null;$original=$null;$out=$null;$temp=$null
    try {
      # No writer may change the render while it is validated and copied.
      $renderStream=[IO.File]::Open($src,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
      $si=Get-Item -LiteralPath $src
      if (([string]$si.LastWriteTimeUtc.Ticks+':'+[string]$si.Length) -ne $req.stamp) { throw 'Render changed after it was queued.' }
      $wi=WaveInfo $renderStream;$sha=HashStream $renderStream
      $original=[IO.File]::Open($dst,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
      $old=WaveInfo $original
      if ($old.channels -ne $wi.channels) { throw 'Channel count changed; update skipped.' }
      if ((HashStream $original) -ne $req.destinationSha) { throw 'Wwise original changed while preparing this update; render again after the other edit finishes.' }
      $original.Dispose();$original=$null
      $temp=Join-Path ([IO.Path]::GetDirectoryName($dst)) ('.wwise-relay-'+[guid]::NewGuid().ToString('N')+'.tmp')
      $out=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
      $renderStream.CopyTo($out);$out.Flush($true)
      if ((HashStream $out) -ne $sha) { throw 'Staged audio failed verification.' }
      $out.Dispose();$out=$null
      # Recheck immediately before the atomic, no-backup replacement.
      $original=[IO.File]::Open($dst,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
      if ((HashStream $original) -ne $req.destinationSha) { throw 'Original changed during replacement preparation.' }
      $original.Dispose();$original=$null
      [IO.File]::Replace($temp,$dst,[System.Management.Automation.Language.NullString]::Value);$temp=$null
      $verify=Inspect $dst $true
      if (!$verify.ok -or $verify.sha -ne $sha) { throw 'Replacement occurred, but readback verification failed. Check the original WAV.' }
      @{ok=$true;sha=$sha;stamp=$verify.stamp;channels=$wi.channels;rate=$wi.rate} | ConvertTo-Json -Compress
    } finally {
      if ($null -ne $renderStream) {$renderStream.Dispose()};if ($null -ne $original) {$original.Dispose()};if ($null -ne $out) {$out.Dispose()}
      if ($null -ne $temp -and [IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
  } else { throw 'Unknown helper operation.' }
} catch { @{ok=$false;error=$_.Exception.Message} | ConvertTo-Json -Compress }
