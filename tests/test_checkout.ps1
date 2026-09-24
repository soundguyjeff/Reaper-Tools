$ErrorActionPreference='Stop'
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../src/windows.ps1'),[ref]$null,[ref]$null)
$fn=$ast.Find({param($n)$n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Refresh-ExistingSource'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$id='{11111111-1111-1111-1111-111111111111}'
$req=@{action='checkout';port=8081;projectId=$id;projectPath='C:\Game\Game.wproj';sourceId=$id;soundId=$id;original='C:\Game\Originals\SFX\audio.wav';platform=$id}
function Invoke-Waapi($call,[switch]$ExistingSourceCheckout) {
 if ($ExistingSourceCheckout) {
  if ($call.uri -ne 'ak.wwise.ui.commands.execute' -or $call.args.command -ne 'SourceControlCheckoutWAV' -or @($call.args.objects).Count -ne 1 -or $call.args.objects[0] -ne $id) { throw 'Wrong checkout scope' }
  $script:checkouts++;return @{ok=$true;data=@{}}
 }
 if ($call.uri -eq 'ak.wwise.core.getProjectInfo') {return @{data=@{directories=@{originals='C:\Game\Originals'}}}}
 if ($call.args.from.ofType) {return @{data=@{return=@(@{id=$id;filePath= $(if ($script:mode -eq 'wrong_project') {'C:\Other.wproj'} else {$req.projectPath})})}}}
 if ($call.args.waql) {
  $owners=@(@{id=$id});if($script:mode -eq 'shared'){$owners+=@{id='other'}}
  return @{data=@{return=$owners}}
 }
 if ($call.options.return -contains 'activeSource') {return @{data=@{return=@(@{activeSource=@{id=$id}})}}}
 return @{data=@{return=@(@{id=$id;type='AudioFileSource';parent=@{id=$id};originalWavFilePath=$req.original})}}
}
function Inspect($path,$hash) {
 $script:reads++
 return @{ok=$true;readOnly=($script:reads -eq 1 -or $script:mode -eq 'still_readonly');sha=$(if($script:mode -eq 'changed' -and $script:reads -gt 1){'changed'}else{'same'});resolvedPath=$path}
}
foreach($mode in @('success','wrong_project','shared','still_readonly','changed')) {
 $script:mode=$mode;$script:reads=0;$script:checkouts=0;$failed=$false
 try {$null=Refresh-ExistingSource $req} catch {$failed=$true}
 if ($mode -eq 'success') {if($failed -or $checkouts -ne 1){throw 'Successful scoped checkout failed'}}
 else {if(!$failed){throw "Unsafe checkout passed: $mode"}}
 if($mode -in @('wrong_project','shared') -and $checkouts -ne 0){throw 'Checkout ran before identity validation'}
 Write-Host "PASS checkout $mode"
}
