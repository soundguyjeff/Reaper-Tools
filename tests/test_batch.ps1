$ErrorActionPreference='Stop'
if ($env:OS -ne 'Windows_NT') {Write-Host 'Native batch filesystem tests require Windows; use the live Mac/Wwise test on macOS.';exit 0}
$root=Join-Path ([IO.Path]::GetTempPath()) ('RelayBatchTest-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($root)
function LoadFunctions($file,$names) {
 $ast=[System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$null,[ref]$null)
 foreach($name in $names) {
  $fn=$ast.Find({param($n)$n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
  . ([scriptblock]::Create($fn.Extent.Text.Replace('function '+$name+'(', 'function global:'+$name+'(').Replace('function '+$name+' {','function global:'+$name+' {')))
 }
}
LoadFunctions (Join-Path $PSScriptRoot 'test_windows.ps1') @('Wave','Wem')
LoadFunctions (Join-Path $PSScriptRoot '../src/windows.ps1') @('Initialize-PathInfo','Get-ReparseTag','Check-ReparseTag','SafePath','HashStream','WaveInfo','AudioHash','MediaHash','Inspect','Invoke-NativeBatch')
function Assert-RequestAlive {}
function Id($n) {return ('{{{0:x8}-1111-1111-1111-111111111111}}' -f $n)}
$project=Id 1;$platform=Id 2;$container=Id 3
$originals=Join-Path $root 'Originals';$sfx=Join-Path $originals 'SFX';$renders=Join-Path $root 'renders'
$null=[IO.Directory]::CreateDirectory($sfx);$null=[IO.Directory]::CreateDirectory($renders)
$sounds=@();$sources=@();$items=@()
for($i=0;$i -lt 10;$i++) {
 $name='Batch_'+$i;$src=Join-Path $renders ($name+'.wav');$dst=Join-Path $sfx ('original_'+$i+'.wav');Wave $src ($i+10);Wave $dst $i
 $sid=Id ($i+10);$aid=Id ($i+30)
 $sounds+=@{id=$sid;name=$name;type='Sound';path=('\Actor-Mixer Hierarchy\Tests\'+$name);parent=@{id=$container};activeSource=@{id=$aid}}
 $sources+=@{id=$aid;type='AudioFileSource';parent=@{id=$sid};originalWavFilePath=$dst;contentHash='{11111111-2222-3333-4444-555555555555}';convertedWemFilePath=(Join-Path $root ('cache'+$i+'.wem'))}
 $items+=Inspect $src $true
}
$req=@{items=$items;projectId=$project;projectPath=(Join-Path $root 'test.wproj');platform=$platform;port=1}
function Invoke-Waapi($call,[switch]$ExistingSourceRefresh,[switch]$ExistingBatch) {
 $script:calls+=,$call
 switch($call.uri) {
 'ak.wwise.core.getProjectInfo' {return @{data=@{directories=@{originals=$originals};platforms=@(@{id=$platform})}}}
 'ak.wwise.core.object.get' {
  $a=$call.args
  if($a.from.ofType){return @{data=@{return=@(@{id=$project;filePath=$req.projectPath})}}}
  if($a.waql -like 'from type Sound*'){return @{data=@{return=$script:sounds}}}
  if($a.waql -like 'from type AudioFileSource*'){
   $owners=$script:sources;if($script:mode -eq 'shared'){$owners=$script:sources+@(@{id=(Id 999);originalWavFilePath=$script:sources[0].originalWavFilePath})}
   return @{data=@{return=$owners}}
  }
  $found=@($script:sounds+$script:sources | Where-Object {$_.id -in $a.from.id})
  return @{data=@{return=$found}}
 }
 'ak.wwise.core.audio.import' {
  if(!$ExistingSourceRefresh -or $call.args.importOperation -ne 'useExisting' -or $call.args.autoAddToSourceControl -ne $false -or $call.args.autoCheckOutToSourceControl -ne $true){throw 'Incorrect native import flags'}
  $files=@();$objects=@()
  foreach($entry in $call.args.imports){
   $source=@($script:sources | Where-Object {$_.id -eq $entry.importLocation})
   if($source.Count -ne 1 -or $entry.objectPath -ne '' -or $entry.importLanguage -ne 'SFX' -or [IO.Path]::GetFileName($entry.audioFile) -ne [IO.Path]::GetFileName($source[0].originalWavFilePath)){throw 'Import can create or redirect audio'}
   [IO.File]::Copy($entry.audioFile,$source[0].originalWavFilePath,$true)
   $files+=,$source[0].originalWavFilePath;$objects+=,@{id=$source[0].id}
  }
  return @{data=@{files=$files;objects=$objects;log=@()}}
 }
 'ak.wwise.core.audio.convert' {
  if(!$ExistingBatch -or $call.args.platforms[0] -ne $platform -or $call.args.languages[0] -ne 'SFX'){throw 'Unscoped conversion'}
  foreach($s in $script:sources){Wem $s.convertedWemFilePath}
  return @{data=@{errors=@()}}
 }
 default {throw 'Unexpected or checkout/save command: '+$call.uri}
 }
}
try {
 foreach($mode in @('normal','shared')){
  $script:mode=$mode;$script:calls=@()
  $result=Invoke-NativeBatch $req
  $expected=if($mode -eq 'shared'){9}else{10}
  if(@($result.items | Where-Object {$_.state -eq 'Converted'}).Count -ne $expected){throw ($result | ConvertTo-Json -Depth 10)}
  if(@($calls | Where-Object {$_.uri -eq 'ak.wwise.core.audio.import'}).Count -ne 1 -or @($calls | Where-Object {$_.uri -eq 'ak.wwise.core.audio.convert'}).Count -ne 1){throw 'Batch regressed to per-file calls'}
  if($calls.Count -gt 10){throw 'Excessive Wwise round trips'}
  Write-Host "PASS $mode batch: $expected files, one import, one conversion, $($calls.Count) total calls, no explicit checkout/save"
 }
 $script:calls=@();$req.items[0].stamp='stale';$result=Invoke-NativeBatch $req
 if(@($calls | Where-Object {$_.uri -eq 'ak.wwise.core.audio.import'}).Count){throw 'Changed render reached import'}
 if(!$result.error){throw 'Stale batch must fail'}
 Write-Host 'PASS stale render prevents the entire native import'
} finally {Remove-Item -LiteralPath $root -Recurse -Force}
