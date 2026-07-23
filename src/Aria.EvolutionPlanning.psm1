Set-StrictMode -Version Latest

$commonPath=Join-Path $PSScriptRoot 'Aria.Common.psm1'
if(-not(Get-Module Aria.Common)){Import-Module $commonPath -DisableNameChecking}
$typedCorePath=Join-Path $PSScriptRoot 'Aria.TypedCore.psm1'
if(-not(Get-Module Aria.TypedCore)){Import-Module $typedCorePath -DisableNameChecking}
$evolutionPath=Join-Path $PSScriptRoot 'Aria.GovernedEvolution.psm1'
if(-not(Get-Module Aria.GovernedEvolution)){Import-Module $evolutionPath -DisableNameChecking}

function Get-AriaPlanningProperty {
    param($Object,[string]$Name,$Default=$null)
    if($null-eq$Object){return $Default}
    $property=$Object.PSObject.Properties|Where-Object{$_.Name-ceq$Name}|Select-Object -First 1
    if($null-eq$property){return $Default}
    $property.Value
}

function Test-AriaEvolutionRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Request)

    $errors=New-Object 'System.Collections.Generic.List[object]'
    if([string](Get-AriaPlanningProperty $Request 'schema')-cne'aria.evolution-request/0.7'){
        [void]$errors.Add((New-AriaStructuredError -Code 'E_EVOLUTION_REQUEST_SCHEMA' -Message 'Unsupported evolution request schema.' -Path '$.schema'))
    }
    foreach($field in @('proposer','targetVersion','resource')){
        if([string]::IsNullOrWhiteSpace([string](Get-AriaPlanningProperty $Request $field))){
            [void]$errors.Add((New-AriaStructuredError -Code 'E_EVOLUTION_REQUEST_FIELD' -Message "Evolution request field '$field' is required." -Path ("$.{0}"-f$field)))
        }
    }
    if(-not(Test-AriaSemanticVersion ([string](Get-AriaPlanningProperty $Request 'targetVersion')))){
        [void]$errors.Add((New-AriaStructuredError -Code 'E_EVOLUTION_REQUEST_VERSION' -Message 'Evolution targetVersion is not semantic.' -Path '$.targetVersion'))
    }

    $capabilityIds=@((Get-AriaPlanningProperty $Request 'capabilityIds' @()))
    if($capabilityIds.Count-eq0){
        [void]$errors.Add((New-AriaStructuredError -Code 'E_EVOLUTION_REQUEST_CAPABILITY' -Message 'At least one capability identity is required.' -Path '$.capabilityIds'))
    }
    foreach($id in $capabilityIds){
        if([string]$id-cnotmatch'^sha256:[a-f0-9]{64}$'){
            [void]$errors.Add((New-AriaStructuredError -Code 'E_EVOLUTION_REQUEST_CAPABILITY' -Message "Invalid capability identity '$id'." -Path '$.capabilityIds'))
        }
    }

    $changes=@((Get-AriaPlanningProperty $Request 'changes' @()))
    if($changes.Count-eq0){
        [void]$errors.Add((New-AriaStructuredError -Code 'E_EVOLUTION_REQUEST_CHANGES' -Message 'At least one requested change is required.' -Path '$.changes'))
    }
    $seen=@{}
    foreach($change in $changes){
        $path=[string](Get-AriaPlanningProperty $change 'path')
        $pathResult=Test-AriaEvolutionPath $path
        if(-not[bool]$pathResult.valid){
            [void]$errors.Add((New-AriaStructuredError -Code 'E_EVOLUTION_REQUEST_PATH' -Message "Unsafe evolution request path '$path'." -Path '$.changes.path'))
            continue
        }
        if($seen.ContainsKey($pathResult.normalized)){
            [void]$errors.Add((New-AriaStructuredError -Code 'E_EVOLUTION_REQUEST_DUPLICATE' -Message "Duplicate evolution request path '$($pathResult.normalized)'." -Path '$.changes.path'))
        }
        else{$seen[$pathResult.normalized]=$true}
        $operation=[string](Get-AriaPlanningProperty $change 'operation')
        if($operation-notin@('write','delete')){
            [void]$errors.Add((New-AriaStructuredError -Code 'E_EVOLUTION_REQUEST_OPERATION' -Message "Unsupported change operation '$operation'." -Path '$.changes.operation'))
        }
        $hasContent=$null-ne($change.PSObject.Properties|Where-Object{$_.Name-ceq'content'}|Select-Object -First 1)
        if($operation-eq'write' -and-not$hasContent){
            [void]$errors.Add((New-AriaStructuredError -Code 'E_EVOLUTION_REQUEST_CONTENT' -Message "Write change '$path' requires content." -Path '$.changes.content'))
        }
        if($operation-eq'delete' -and$hasContent -and $null-ne(Get-AriaPlanningProperty $change 'content')){
            [void]$errors.Add((New-AriaStructuredError -Code 'E_EVOLUTION_REQUEST_CONTENT' -Message "Delete change '$path' cannot contain replacement content." -Path '$.changes.content'))
        }
    }

    $evidence=@((Get-AriaPlanningProperty $Request 'evidence' @()))
    if($evidence.Count-eq0){
        [void]$errors.Add((New-AriaStructuredError -Code 'E_EVOLUTION_REQUEST_EVIDENCE' -Message 'At least one evidence reference is required.' -Path '$.evidence'))
    }
    foreach($item in $evidence){
        if([string]::IsNullOrWhiteSpace([string](Get-AriaPlanningProperty $item 'kind')) -or
           [string]::IsNullOrWhiteSpace([string](Get-AriaPlanningProperty $item 'id')) -or
           [string](Get-AriaPlanningProperty $item 'digest')-cnotmatch'^[a-f0-9]{64}$'){
            [void]$errors.Add((New-AriaStructuredError -Code 'E_EVOLUTION_REQUEST_EVIDENCE' -Message 'Evidence requires kind, id, and a lowercase SHA-256 digest.' -Path '$.evidence'))
        }
    }

    [pscustomobject][ordered]@{valid=($errors.Count-eq0);errors=@($errors.ToArray())}
}

function New-AriaEvolutionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Request,
        [Parameter(Mandatory=$true)][string]$WorkspaceRoot,
        [Parameter(Mandatory=$true)][string]$BaseCommit
    )

    $validation=Test-AriaEvolutionRequest $Request
    if(-not[bool]$validation.valid){
        throw "ARIA evolution request rejected: $(@($validation.errors|ForEach-Object{$_.code+': '+$_.message})-join'; ')"
    }
    if($BaseCommit-cnotmatch'^[a-fA-F0-9]{40,64}$'){throw 'ARIA evolution planning requires an exact Git commit identity.'}

    $workspace=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $WorkspaceRoot).Path)
    $beforeFiles=New-Object 'System.Collections.Generic.List[object]'
    $changes=New-Object 'System.Collections.Generic.List[object]'
    $rollbacks=New-Object 'System.Collections.Generic.List[object]'
    foreach($requested in @((Get-AriaPlanningProperty $Request 'changes' @())|Sort-Object path)){
        $path=[string](Get-AriaPlanningProperty $requested 'path')
        $operation=[string](Get-AriaPlanningProperty $requested 'operation')
        $resolved=Resolve-AriaConfinedPath -WorkspaceRoot $workspace -Scope '.' -RequestedPath $path
        $exists=Test-Path -LiteralPath $resolved -PathType Leaf
        if($operation-eq'delete' -and-not$exists){throw "ARIA evolution delete target does not exist: $path"}
        if(Test-Path -LiteralPath $resolved -PathType Container){throw "ARIA evolution target is a directory: $path"}
        $before=if($exists){[IO.File]::ReadAllText($resolved)}else{$null}
        if($exists){[void]$beforeFiles.Add([pscustomobject]@{path=$path;content=$before})}
        $after=if($operation-eq'write'){[string](Get-AriaPlanningProperty $requested 'content')}else{$null}
        $change=New-AriaEvolutionChange -Path $path -Operation $operation -BeforeContent $before -AfterContent $after
        [void]$changes.Add($change)
        if($exists){
            [void]$rollbacks.Add((New-AriaEvolutionRollbackStep -Path $path -Operation write -ExpectedDigest $change.afterDigest -RestoreContent $before))
        }
        else{
            [void]$rollbacks.Add((New-AriaEvolutionRollbackStep -Path $path -Operation delete -ExpectedDigest $change.afterDigest -RestoreContent $null))
        }
    }

    $original=New-AriaRepositorySnapshot -Files @($beforeFiles.ToArray())
    $proposal=New-AriaEvolutionProposal `
        -Proposer ([string](Get-AriaPlanningProperty $Request 'proposer')) `
        -BaseCommit $BaseCommit `
        -TargetVersion ([string](Get-AriaPlanningProperty $Request 'targetVersion')) `
        -Resource ([string](Get-AriaPlanningProperty $Request 'resource')) `
        -RequestedEffects @('repository.write') `
        -CapabilityIds @((Get-AriaPlanningProperty $Request 'capabilityIds' @())) `
        -Changes @($changes.ToArray()) `
        -Evidence @((Get-AriaPlanningProperty $Request 'evidence' @())) `
        -RollbackPlan @($rollbacks.ToArray())
    $proposalValidation=Test-AriaEvolutionProposal $proposal
    if(-not[bool]$proposalValidation.valid){throw "Generated proposal failed verification: $(@($proposalValidation.errors.code)-join', ')"}
    $candidate=Invoke-AriaEvolutionChanges -Snapshot $original -Changes @($changes.ToArray())
    if(-not[bool]$candidate.valid){throw "Generated candidate failed verification: $(@($candidate.errors.code)-join', ')"}
    $rollback=Test-AriaEvolutionRollback -OriginalSnapshot $original -CandidateSnapshot $candidate.snapshot -RollbackPlan @($rollbacks.ToArray())
    if(-not[bool]$rollback.valid){throw "Generated rollback proof failed: $(@($rollback.errors.code)-join', ')"}
    $diff=New-AriaEvolutionSemanticDiff -OriginalSnapshot $original -CandidateSnapshot $candidate.snapshot

    $identity=[ordered]@{
        schema='aria.evolution-plan-record/0.7'
        state='awaiting-authorization'
        proposalId=$proposal.id
        baseCommit=$BaseCommit.ToLowerInvariant()
        originalSnapshotId=$original.id
        candidateSnapshotId=$candidate.snapshot.id
        semanticDiff=$diff
        rollbackVerified=$true
        requiredGates=@($proposal.requiredGates)
    }
    $record=[pscustomobject][ordered]@{
        schema=$identity.schema
        state=$identity.state
        proposalId=$identity.proposalId
        baseCommit=$identity.baseCommit
        originalSnapshotId=$identity.originalSnapshotId
        candidateSnapshotId=$identity.candidateSnapshotId
        semanticDiff=$identity.semanticDiff
        rollbackVerified=$identity.rollbackVerified
        requiredGates=@($identity.requiredGates)
        id="sha256:$(Get-AriaSha256Hex (ConvertTo-AriaStableJson $identity))"
    }
    [pscustomobject][ordered]@{
        request=$Request
        proposal=$proposal
        originalSnapshot=$original
        candidateSnapshot=$candidate.snapshot
        record=$record
    }
}

function Write-AriaEvolutionPlanRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Plan,
        [Parameter(Mandatory=$true)][string]$WorkspaceRoot
    )

    $digest=([string]$Plan.proposal.id)-replace'^sha256:',''
    if($digest-cnotmatch'^[a-f0-9]{64}$'){throw 'Cannot persist an evolution plan without a valid proposal identity.'}
    $root=Join-Path ([IO.Path]::GetFullPath($WorkspaceRoot)) '.aria/evolution'
    $directory=Join-Path $root $digest
    if(-not(Test-Path -LiteralPath $directory -PathType Container)){New-Item -ItemType Directory -Path $directory -Force|Out-Null}
    $documents=[ordered]@{
        'request.json'=$Plan.request
        'proposal.json'=$Plan.proposal
        'original-snapshot.json'=$Plan.originalSnapshot
        'candidate-snapshot.json'=$Plan.candidateSnapshot
        'plan.json'=$Plan.record
    }
    foreach($entry in $documents.GetEnumerator()){
        $path=Join-Path $directory $entry.Key
        $text=(ConvertTo-AriaStableJson $entry.Value)+[Environment]::NewLine
        if(Test-Path -LiteralPath $path -PathType Leaf){
            $existing=Read-AriaUtf8Text $path
            if($existing-cne$text){throw "Evolution record identity collision at '$path'."}
        }
        else{Write-AriaUtf8NoBom -Path $path -Text $text}
    }
    [pscustomobject][ordered]@{directory=$directory;proposalId=$Plan.proposal.id;recordId=$Plan.record.id;state=$Plan.record.state}
}

function Invoke-AriaEvolutionPlanFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$WorkspaceRoot,
        [Parameter(Mandatory=$true)][string]$BaseCommit
    )

    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "Evolution request not found: $Path"}
    try{$request=Read-AriaUtf8Text $Path|ConvertFrom-Json}
    catch{throw "Evolution request JSON is invalid: $($_.Exception.Message)"}
    $plan=New-AriaEvolutionPlan -Request $request -WorkspaceRoot $WorkspaceRoot -BaseCommit $BaseCommit
    $persisted=Write-AriaEvolutionPlanRecord -Plan $plan -WorkspaceRoot $WorkspaceRoot
    [pscustomobject][ordered]@{plan=$plan;persisted=$persisted}
}

Export-ModuleMember -Function `
    Test-AriaEvolutionRequest, `
    New-AriaEvolutionPlan, `
    Write-AriaEvolutionPlanRecord, `
    Invoke-AriaEvolutionPlanFile
