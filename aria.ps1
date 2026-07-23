[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Command = 'help',
    [Parameter(Position=1)][string]$Path,
    [Parameter(Position=2)][string]$RequestPath,
    [string]$Out,
    [string]$Policy,
    [string]$Capability,
    [string]$Authorization,
    [string]$IssuerPolicy,
    [string]$Workspace,
    [switch]$Strict,
    [switch]$VerboseOutput
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not $Policy) { $Policy = Join-Path $root 'aria.policy.json' }
if (-not $Workspace) { $Workspace = $root }
if (-not (Test-Path -LiteralPath $Workspace -PathType Container)) { throw "ARIA workspace does not exist or is not a directory: $Workspace" }
$workspaceRoot = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Workspace).Path)
$script:VerboseOutput = $VerboseOutput -or $env:ARIA_VERBOSE -eq '1'

Import-Module (Join-Path $root 'src/Aria.Display.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Etherflow.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Common.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Transmission.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.EventSpine.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Gitflow.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Lexer.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Parser.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Semantics.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Bytecode.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Gate.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.VM.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.EvolutionPlanning.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Intent.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.IntentVerifier.psm1') -Force -DisableNameChecking

$null = Initialize-AriaEventSpine -WorkspaceRoot $workspaceRoot -Profile (Get-AriaOperatorProfile) -Persist

function Show-AriaHelp {
    Write-AriaBanner -Title 'ARIA / LANGUAGE LABORATORY'
    @'
  aria doctor [-Workspace <repository>] [-Strict]
  aria verify
  aria manifest
  aria test
  aria profile
  aria transmit <provider.json>
  aria events
  aria pull|push|sync
  aria gate|check <program.aria> [-Workspace <repository>] [-Strict]
  aria compile|build <program.aria> [-Out <program.ariac>] [-Workspace <repository>] [-Strict]
  aria run|start|trace <program.aria> [-Out <program.ariac>] [-Workspace <repository>] [-Strict]
  aria connect [program.aria] [-Workspace <repository>] [-Strict]
  aria exec <program.ariac> [-Workspace <repository>] [-Strict]
  aria inspect <program.ariac>
  aria graph <program.aria|program.ariac>
  aria evolve plan <request.json> [-Workspace <repository>]
  aria evolve verify <proposal-id> -Capability <bundle.json> -Authorization <authorization.json> -IssuerPolicy <verification-policy.json>
  aria intent verify <intent-verification-bundle.json> [-Workspace <repository>]
  aria init <ProgramName>

  ARIA 0.4 adds verified human-agent connection contracts: intent, proposal, consent, and closure.
  aria version

  Add -VerboseOutput, or set ARIA_VERBOSE=1, to expose raw diagnostic detail.
'@ | Write-Host
}

function Assert-AriaRepositoryManifest {
    $manifest = Test-AriaManifest -Root $root
    Write-AriaStage -Name 'repository manifest' -State $(if ($manifest.valid) { 'Pass' } else { 'Fail' }) -Detail ("{0}/{1} files" -f $manifest.actual, $manifest.expected)
    if ($script:VerboseOutput) { Write-AriaKeyValue -Key 'manifest' -Value $manifest.message }
    if (-not $manifest.valid) { throw "ARIA repository integrity failed: $($manifest.message)" }
    return $manifest
}

try {
    switch ($Command.ToLowerInvariant()) {
        'pull' {
            $null = Invoke-AriaGitPull -RepositoryRoot $root -Render -VerboseBuffer:$script:VerboseOutput
        }
        'push' {
            $null = Invoke-AriaGitPush -RepositoryRoot $root -Render -VerboseBuffer:$script:VerboseOutput
        }
        'sync' {
            $null = Invoke-AriaGitSync -RepositoryRoot $root -Render -VerboseBuffer:$script:VerboseOutput
        }
        'evolve' {
            switch($Path){
                'plan' {
                    if(-not$RequestPath){throw 'evolve plan requires an evolution request JSON path.'}
                    $clock=[Diagnostics.Stopwatch]::StartNew()
                    Write-AriaBanner -Title 'ARIA / EVOLUTION PLAN' -Subtitle 'content-addressed proposal · rollback proof · no repository mutation'
                    Write-AriaTreeStage -Name 'request verification' -State Pulse -Detail $RequestPath
                    $null=Assert-AriaGitClean -RepositoryRoot $workspaceRoot
                    $head=Get-AriaGitHead -RepositoryRoot $workspaceRoot
                    $result=Invoke-AriaEvolutionPlanFile -Path $RequestPath -WorkspaceRoot $workspaceRoot -BaseCommit $head
                    Write-AriaTreeStage -Name 'proposal identity' -State Pass -Detail $result.plan.proposal.id
                    Write-AriaTreeStage -Name 'candidate snapshot' -State Pass -Detail $result.plan.candidateSnapshot.id
                    Write-AriaTreeStage -Name 'rollback proof' -State Pass -Detail 'original snapshot reproduced'
                    Write-AriaTreeStage -Name 'authorization' -State Warn -Detail 'required before verify or apply'
                    $clock.Stop()
                    Write-AriaSummary -Title 'PLAN RECORDED' -Passed $true -Detail $result.persisted.directory -Duration $clock.Elapsed
                }
                'verify' {
                    if(-not$RequestPath){throw 'evolve verify requires a proposal identity.'}
                    if(-not$Capability-or-not$Authorization-or-not$IssuerPolicy){
                        throw 'evolve verify requires -Capability, -Authorization, and -IssuerPolicy files.'
                    }
                    $clock=[Diagnostics.Stopwatch]::StartNew()
                    Write-AriaBanner -Title 'ARIA / EVOLUTION VERIFY' -Subtitle 'record integrity · capability authority · explicit human authorization'
                    Write-AriaTreeStage -Name 'plan reconstruction' -State Pulse -Detail $RequestPath
                    $null=Assert-AriaGitClean -RepositoryRoot $workspaceRoot
                    $head=Get-AriaGitHead -RepositoryRoot $workspaceRoot
                    $result=Invoke-AriaEvolutionVerificationFiles `
                        -ProposalId $RequestPath `
                        -WorkspaceRoot $workspaceRoot `
                        -CurrentCommit $head `
                        -CapabilityPath $Capability `
                        -AuthorizationPath $Authorization `
                        -VerificationPolicyPath $IssuerPolicy
                    Write-AriaTreeStage -Name 'record integrity' -State Pass -Detail $result.plan.record.id
                    Write-AriaTreeStage -Name 'capability authority' -State Pass -Detail $result.verification.authorityDecision.id
                    Write-AriaTreeStage -Name 'human authorization' -State Pass -Detail $result.verification.authorization.id
                    Write-AriaTreeStage -Name 'repository mutation' -State Info -Detail 'none'
                    $clock.Stop()
                    Write-AriaSummary -Title 'EVOLUTION AUTHORIZED' -Passed $true -Detail $result.persisted.verificationId -Duration $clock.Elapsed
                }
                default{throw "evolve supports 'plan' and 'verify'."}
            }
        }
        'intent' {
            if($Path-cne'verify'){throw "intent supports 'verify'."}
            if(-not$RequestPath){throw 'intent verify requires an intent verification bundle JSON path.'}
            $clock=[Diagnostics.Stopwatch]::StartNew()
            Write-AriaBanner -Title 'ARIA / INTENT VERIFY' -Subtitle 'declared objective · independent challenge · evidence-derived verdict'
            Write-AriaTreeStage -Name 'artifact identities' -State Pulse -Detail $RequestPath
            $result=Invoke-AriaIntentVerificationFile -Path $RequestPath -WorkspaceRoot $workspaceRoot
            Write-AriaTreeStage -Name 'interpretation binding' -State $(if($result.satisfied){'Pass'}else{'Fail'}) -Detail $result.proof.interpretationId
            Write-AriaTreeStage -Name 'authority ceiling' -State $(if('E_INTENT_EXCESS_AUTHORITY'-in@($result.errors|ForEach-Object{$_.code})){'Fail'}else{'Pass'}) -Detail 'declared effects compared'
            Write-AriaTreeStage -Name 'ambiguity and challenge' -State $(if(@($result.errors|ForEach-Object{$_.code}|Where-Object{$_-like'E_INTENT_AMBIGUITY*'-or$_-like'E_INTENT_CHALLENGE*'}).Count){'Fail'}else{'Pass'}) -Detail 'material disagreement requires human resolution'
            Write-AriaTreeStage -Name 'derived obligations' -State $(if($result.satisfied){'Pass'}else{'Fail'}) -Detail ("{0} evaluated" -f @($result.proof.obligations).Count)
            Write-AriaTreeStage -Name 'proof record' -State Info -Detail $result.proofPath
            $clock.Stop()
            Write-AriaSummary -Title $(if($result.satisfied){'INTENT SATISFIED'}else{'INTENT REJECTED'}) -Passed ([bool]$result.satisfied) -Detail $result.proof.id -Duration $clock.Elapsed
            if(-not$result.satisfied){throw ('Intent verification rejected the program: '+(@($result.errors|ForEach-Object{$_.code}|Sort-Object -Unique)-join', '))}
        }
        'profile' {
            $profile = Get-AriaRuntimeProfile
            if ($profile.mode -eq 'machine') {
                Write-Output (ConvertTo-AriaJson -Value $profile)
            }
            else {
                Write-AriaBanner -Title 'ARIA / OPERATOR PROFILE' -Subtitle 'adaptive terminal contract'
                Write-AriaTreeStage -Name 'mode' -State Pass -Detail $profile.mode
                Write-AriaTreeStage -Name 'terminal width' -State Info -Detail ([string]$profile.width)
                Write-AriaTreeStage -Name 'interactive' -State $(if($profile.interactive){'Pass'}else{'Info'}) -Detail ([string]$profile.interactive)
                Write-AriaTreeStage -Name 'unicode' -State $(if($profile.unicode){'Pass'}else{'Warn'}) -Detail ([string]$profile.unicode)
                Write-AriaTreeStage -Name 'animation' -State Info -Detail ([string]$profile.animation)
                Write-AriaSummary -Title 'PROFILE RESOLVED' -Passed $true -Detail $profile.mode
            }
        }
        'transmit' {
            if (-not $Path) { throw 'transmit requires a provider JSON path.' }
            $profile = Get-AriaRuntimeProfile
            $record = Import-AriaTransmissionPayload -Path $Path
            [byte[]]$bytes = ConvertTo-AriaTransmissionBytes -Transmission $record
            $folder = Join-Path $workspaceRoot '.aria/transmissions'
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            $artifact = Join-Path $folder ($record.digest + '.ariat')
            [IO.File]::WriteAllBytes($artifact,$bytes)
            $verified = Read-AriaTransmissionBytes -Bytes ([IO.File]::ReadAllBytes($artifact))
            $null = Send-AriaEvent -Domain transmission -Phase normalize -State ACTIVE -Energy handshake -Information $verified.channel -Coherence 'provider normalized' -Source 'aria.transmit' -Data $verified -Render
            $null = Send-AriaEvent -Domain transmission -Phase artifact -State PASS -Energy compression -Information ([IO.Path]::GetFileName($artifact)) -Coherence 'payload sealed' -Source 'aria.transmit' -Data ([pscustomobject][ordered]@{path=$artifact;bytes=$bytes.Length}) -Render
            $null = Send-AriaEvent -Domain transmission -Phase provenance -State PASS -Energy verification -Information $verified.digest -Coherence 'integrity confirmed' -Source 'aria.transmit' -Data $verified -Render
            if ($profile.mode -eq 'machine') { Write-AriaTransmissionView -Transmission $verified -Profile $profile }
            if ($script:VerboseOutput -and $profile.mode -ne 'machine') {
                Write-AriaKeyValue -Key 'artifact' -Value $artifact
                Write-AriaKeyValue -Key 'compressed bytes' -Value ([string]$bytes.Length)
            }
        }        'events' {
            $events = @(Read-AriaEventLedger -WorkspaceRoot $workspaceRoot)
            if ($events.Count -eq 0) {
                $null = Send-AriaEvent -Domain spine -Phase ledger -State INFO -Energy dormant -Information 'no persisted events' -Coherence 'ledger empty' -Source 'aria.events' -Render
            }
            else {
                $start = [Math]::Max(0,$events.Count - 20)
                for($i=$start;$i-lt$events.Count;$i++){
                    Publish-AriaEvent -Event $events[$i] -Render
                }
            }
        }        'doctor' {
            $clock = [Diagnostics.Stopwatch]::StartNew()
            Write-AriaBanner -Title 'ARIA / DOCTOR'
            Write-AriaTreeStage -Name 'host inspection' -State Pulse -Detail 'PowerShell + policy + container'
            if ($PSVersionTable.PSVersion.Major -lt 5) { throw 'ARIA requires Windows PowerShell 5.1 or PowerShell 7.' }
            Write-AriaKeyValue -Key 'PowerShell' -Value ([string]$PSVersionTable.PSVersion)
            Write-AriaKeyValue -Key 'Compiler' -Value (Get-AriaCompilerVersion)
            Write-AriaKeyValue -Key 'Workspace' -Value $workspaceRoot
            Write-AriaKeyValue -Key 'Policy' -Value (Resolve-Path -LiteralPath $Policy).Path
            $null = Get-AriaPolicy -PolicyPath $Policy
            Write-AriaTreeStage -Name 'policy document' -State Pass -Detail 'deny by default'
            $probe = Join-Path ([System.IO.Path]::GetTempPath()) ('aria-gzip-' + [guid]::NewGuid().ToString('N') + '.bin')
            try {
                $sample = [pscustomobject][ordered]@{
                    format = 'aria.bytecode'; containerVersion = 1; compilerVersion = Get-AriaCompilerVersion
                    specVersion = (Get-AriaLock).specVersion; programName = 'DoctorProbe'; programVersion = '0.0.0'
                    sourceHash = ('0' * 64); irHash = ('0' * 64); moduleName = 'Doctor'; moduleVersion = '0.0.0'; entry = 'Main'; constants = @(); memories = @()
                    capabilities = @(); agents = @(); connections = @(); graphs = @(); functions = @(); instructions = @([pscustomobject][ordered]@{ op = 'HALT'; line = 0 })
                }
                Write-AriaContainer -Bytes (ConvertTo-AriaContainerBytes -BytecodeModel $sample) -Path $probe
                $container = Read-AriaContainer -Path $probe
                $verification = Test-AriaBytecodeModel -BytecodeModel $container.bytecode
                if (-not $verification.valid) { throw ('Doctor bytecode verification failed: ' + ($verification.errors -join '; ')) }
            }
            finally { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue }
            Write-AriaTreeStage -Name 'compressed container' -State Pass -Detail 'gzip + SHA-256 + bytecode'
            if ($Strict) { $null = Assert-AriaRepositoryManifest }
            $clock.Stop()
            Write-AriaSummary -Title 'SYSTEM READY' -Passed $true -Detail 'all gates online' -Duration $clock.Elapsed
        }
        'verify' {
            Write-AriaBanner -Title 'ARIA / VERIFY'
            $null = Assert-AriaRepositoryManifest
            Write-AriaSummary -Title 'INTEGRITY VERIFIED' -Passed $true
        }
        'manifest' {
            Write-AriaBanner -Title 'ARIA / MANIFEST'
            Write-AriaTreeStage -Name 'repository hashing' -State Pulse -Detail 'SHA-256 tree'
            $count = Update-AriaManifest -Root $root
            Write-AriaSummary -Title 'MANIFEST SEALED' -Passed $true -Detail ("{0} files" -f $count)
        }
        'test' {
            & (Join-Path $root 'tests/Run-Tests.ps1') -VerboseOutput:$script:VerboseOutput
        }
        { $_ -in @('gate','check') } {
            if (-not $Path) { throw 'gate requires a .aria source path.' }
            $clock = [Diagnostics.Stopwatch]::StartNew()
            Write-AriaBanner -Title 'ARIA / GATE'
            $null = Send-AriaEvent -Domain compiler -Phase gate -State ACTIVE -Energy analysis -Information $Path -Coherence 'semantic gate open' -Source 'aria.gate' -Render
            $result = Invoke-AriaGate -SourcePath $Path -PolicyPath $Policy -WorkspaceRoot $workspaceRoot -StrictRepository:$Strict
            $null = Send-AriaEvent -Domain verifier -Phase semantics -State PASS -Energy validation -Information $result.bytecode.programName -Coherence 'source accepted' -Source 'aria.gate' -Data ([pscustomobject][ordered]@{buildHash=$result.buildHash}) -Render
            $clock.Stop()
            if ($script:VerboseOutput) { Write-AriaKeyValue -Key 'build hash' -Value $result.buildHash }
        }
        { $_ -in @('compile','build') } {
            if (-not $Path) { throw 'compile requires a .aria source path.' }
            $clock = [Diagnostics.Stopwatch]::StartNew()
            Write-AriaBanner -Title 'ARIA / COMPILE'
            $null = Send-AriaEvent -Domain compiler -Phase compile -State ACTIVE -Energy translation -Information $Path -Coherence 'compiler engaged' -Source 'aria.compile' -Render
            $result = Invoke-AriaCompile -SourcePath $Path -PolicyPath $Policy -OutputPath $Out -WorkspaceRoot $workspaceRoot -StrictRepository:$Strict
            $null = Send-AriaEvent -Domain compiler -Phase artifact -State PASS -Energy compression -Information ([IO.Path]::GetFileName($result.artifactPath)) -Coherence 'bytecode sealed' -Source 'aria.compile' -Data ([pscustomobject][ordered]@{path=$result.artifactPath;program=$result.gate.bytecode.programName}) -Render
            $clock.Stop()
        }
        { $_ -in @('run','start','trace') } {
            if (-not $Path) { $Path = Join-Path $root 'examples/hello.aria' }
            $clock = [Diagnostics.Stopwatch]::StartNew()
            Write-AriaBanner -Title 'ARIA / RUN'
            $null = Send-AriaEvent -Domain compiler -Phase compile -State ACTIVE -Energy translation -Information $Path -Coherence 'runtime build open' -Source 'aria.run' -Render
            $compiled = Invoke-AriaCompile -SourcePath $Path -PolicyPath $Policy -OutputPath $Out -WorkspaceRoot $workspaceRoot -StrictRepository:$Strict
            $null = Send-AriaEvent -Domain verifier -Phase artifact -State PASS -Energy verification -Information ([IO.Path]::GetFileName($compiled.artifactPath)) -Coherence 'bytecode accepted' -Source 'aria.run' -Data ([pscustomobject][ordered]@{path=$compiled.artifactPath}) -Render
            $null = Send-AriaEvent -Domain policy -Phase authority -State ACTIVE -Energy authorization -Information ([IO.Path]::GetFileName($Policy)) -Coherence 'runtime policy engaged' -Source 'aria.run' -Render
            $null = Send-AriaEvent -Domain vm -Phase execute -State ACTIVE -Energy execution -Information $compiled.gate.bytecode.programName -Coherence 'local VM active' -Source 'aria.run' -Render
            $null = Invoke-AriaArtifact -Path $compiled.artifactPath -PolicyPath $Policy -WorkspaceRoot $workspaceRoot
            $null = Send-AriaEvent -Domain vm -Phase halt -State PASS -Energy completion -Information $compiled.gate.bytecode.programName -Coherence 'deterministic halt' -Source 'aria.run' -Render
            $clock.Stop()
        }
        'connect' {
            if (-not $Path) { $Path = Join-Path $root 'examples/connection.aria' }
            $clock = [Diagnostics.Stopwatch]::StartNew()
            Write-AriaBanner -Title 'ARIA / CONNECTION' -Subtitle 'human intent · agent proposal · explicit consent · deterministic closure'
            $null = Send-AriaEvent -Domain connection -Phase intent -State ACTIVE -Energy intention -Information $Path -Coherence 'human intent received' -Source 'aria.connect' -Render
            $compiled = Invoke-AriaCompile -SourcePath $Path -PolicyPath $Policy -OutputPath $Out -WorkspaceRoot $workspaceRoot -StrictRepository:$Strict
            $null = Send-AriaEvent -Domain connection -Phase proposal -State PASS -Energy negotiation -Information $compiled.gate.bytecode.programName -Coherence 'verified proposal formed' -Source 'aria.connect' -Data ([pscustomobject][ordered]@{artifact=$compiled.artifactPath}) -Render
            $null = Send-AriaEvent -Domain connection -Phase consent -State ACTIVE -Energy authorization -Information 'explicit contract' -Coherence 'consent evaluated by runtime' -Source 'aria.connect' -Render
            $null = Invoke-AriaArtifact -Path $compiled.artifactPath -PolicyPath $Policy -WorkspaceRoot $workspaceRoot
            $null = Send-AriaEvent -Domain connection -Phase closure -State PASS -Energy completion -Information $compiled.gate.bytecode.programName -Coherence 'deterministic closure' -Source 'aria.connect' -Render
            $clock.Stop()
        }
        'exec' {
            if (-not $Path) { throw 'exec requires an .ariac artifact path.' }
            $clock = [Diagnostics.Stopwatch]::StartNew()
            Write-AriaBanner -Title 'ARIA / EXECUTE'
            if ($Strict) { $null = Assert-AriaRepositoryManifest }
            $null = Send-AriaEvent -Domain verifier -Phase artifact -State ACTIVE -Energy verification -Information $Path -Coherence 'artifact inspection open' -Source 'aria.exec' -Render
            $null = Send-AriaEvent -Domain policy -Phase authority -State ACTIVE -Energy authorization -Information ([IO.Path]::GetFileName($Policy)) -Coherence 'execution policy engaged' -Source 'aria.exec' -Render
            $null = Send-AriaEvent -Domain vm -Phase execute -State ACTIVE -Energy execution -Information ([IO.Path]::GetFileName($Path)) -Coherence 'artifact entered VM' -Source 'aria.exec' -Render
            $null = Invoke-AriaArtifact -Path $Path -PolicyPath $Policy -WorkspaceRoot $workspaceRoot
            $null = Send-AriaEvent -Domain vm -Phase halt -State PASS -Energy completion -Information ([IO.Path]::GetFileName($Path)) -Coherence 'deterministic halt' -Source 'aria.exec' -Render
            $clock.Stop()
        }
        'inspect' {
            if (-not $Path) { throw 'inspect requires an .ariac artifact path.' }
            Write-AriaBanner -Title 'ARIA / DISASSEMBLY'
            $container = Read-AriaContainer -Path $Path
            $verification = Test-AriaBytecodeModel -BytecodeModel $container.bytecode
            if (-not $verification.valid) { throw ('ARIA bytecode verifier rejected artifact: ' + ($verification.errors -join '; ')) }
            Write-AriaTreeStage -Name 'artifact verification' -State Pass -Detail $container.bytecode.programName
            Write-Host (Format-AriaDisassembly -Container $container)
        }
        'graph' {
            if (-not $Path) { throw 'graph requires a .aria source or .ariac artifact path.' }
            Write-AriaBanner -Title 'ARIA / GRAPH' -Subtitle 'typed semantic topology · glyph registry · local program model'
            if ([System.IO.Path]::GetExtension($Path).ToLowerInvariant() -eq '.ariac') {
                $container = Read-AriaContainer -Path $Path
                $verification = Test-AriaBytecodeModel -BytecodeModel $container.bytecode
                if (-not $verification.valid) { throw ('ARIA bytecode verifier rejected artifact: ' + ($verification.errors -join '; ')) }
                $graphs = @($container.bytecode.graphs)
            }
            else {
                $gate = Invoke-AriaGate -SourcePath $Path -PolicyPath $Policy -WorkspaceRoot $workspaceRoot -Quiet -StrictRepository:$Strict
                $graphs = @($gate.bytecode.graphs)
            }
            if ($graphs.Count -eq 0) { Write-AriaTreeStage -Name 'semantic graph' -State Warn -Detail 'program declares no graphs' -Last }
            for ($graphIndex = 0; $graphIndex -lt $graphs.Count; $graphIndex++) {
                $graph = $graphs[$graphIndex]
                $isLastGraph = $graphIndex -eq ($graphs.Count - 1)
                Write-AriaTreeText -Text ("graph {0}" -f $graph.name) -Glyph '⌬' -Color Magenta -Last:$isLastGraph
                $items = New-Object System.Collections.Generic.List[object]
                foreach ($node in @($graph.nodes)) { $items.Add([pscustomobject]@{ text = ("{0} {1} {2}" -f $node.glyph, $node.nodeKind, $node.name); glyph = $node.glyph }) }
                foreach ($link in @($graph.links)) { $items.Add([pscustomobject]@{ text = ("{0} → {1} · {2}" -f $link.source, $link.target, $link.relation); glyph = '∿' }) }
                for ($itemIndex = 0; $itemIndex -lt $items.Count; $itemIndex++) {
                    Write-AriaTreeText -Text $items[$itemIndex].text -Glyph $items[$itemIndex].glyph -Depth 1 -Last:($itemIndex -eq ($items.Count - 1))
                }
            }
            Write-AriaSummary -Title 'GRAPH RESOLVED' -Passed $true -Detail ("{0} graph(s)" -f $graphs.Count)
        }
        'init' {
            if (-not $Path) { throw 'init requires a program name.' }
            if ($Path -notmatch '^[A-Za-z_][A-Za-z0-9_.-]*$') { throw 'Program name is not a valid ARIA identifier.' }
            $target = Join-Path (Get-Location) ($Path + '.aria')
            if (Test-Path -LiteralPath $target) { throw "File already exists: $target" }
            $template = @"
aria 0.4.0
module $Path version 0.1.0
program $Path version 0.1.0
entry Main

memory Project {
  status: Text = "new"
}

agent architect {
}

connection HumanAI {
  operator = "human"
  agent = "architect"
  protocol = "intent-proposal-consent"
}

graph System {
  node ◉ operator human
  node ⟁ agent architect
  link human -> architect as authorizes
}

flow Main {
  connect HumanAI
  intent HumanAI <- "Create $Path through shared understanding."
  propose HumanAI <- "Compile a verified local program before any external effect."
  consent HumanAI <- true
  disconnect HumanAI

  signal pulse "language core"
  emit "$Path online."
  remember Project.status = "active"
  signal pass "memory online"
}
"@
            Write-AriaUtf8NoBom -Path $target -Text (Normalize-AriaText -Text $template)
            Write-AriaBanner -Title 'ARIA / INITIALIZE'
            Write-AriaSummary -Title 'PROGRAM CREATED' -Passed $true -Detail $target
        }
        'version' {
            $lock = Get-Content -LiteralPath (Join-Path $root 'aria.lock.json') -Raw | ConvertFrom-Json
            Write-AriaBanner -Title 'ARIA / VERSION'
            Write-AriaKeyValue -Key 'Compiler' -Value (Get-AriaCompilerVersion)
            Write-AriaKeyValue -Key 'Spec' -Value ([string]$lock.specVersion)
            Write-AriaKeyValue -Key 'Container' -Value ([string]$lock.containerVersion)
        }
        'help' { Show-AriaHelp }
        default { Show-AriaHelp; throw "Unknown ARIA command '$Command'." }
    }
}
catch {
    Write-Host ''
    Write-AriaTreeStage -Name 'ARIA pipeline' -State Fail -Detail $_.Exception.Message
    if ($script:VerboseOutput) { Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray }
    exit 1
}
