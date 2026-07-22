[CmdletBinding()]
param([switch]$VerboseOutput)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

Import-Module (Join-Path $root 'src/Aria.Display.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Common.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Lexer.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Parser.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Semantics.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Bytecode.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Gate.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.VM.psm1') -Force -DisableNameChecking

$script:Passed = 0
$script:Failed = 0
$script:SuiteClock = [Diagnostics.Stopwatch]::StartNew()
Write-AriaBanner -Title 'ARIA / CONFORMANCE' -Subtitle 'compiler · verifier · policy · memory · virtual machine'
Write-AriaTreeStage -Name 'test lattice' -State Pulse -Detail '42 deterministic gates'
function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        & $Body
        $clock.Stop()
        Write-AriaTreeStage -Name $Name -State Pass -Duration $clock.Elapsed
        $script:Passed++
    }
    catch {
        $clock.Stop()
        Write-AriaTreeStage -Name $Name -State Fail -Detail $_.Exception.Message -Duration $clock.Elapsed
        if ($VerboseOutput) { Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray }
        $script:Failed++
    }
}
function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Assert-Equal { param($Expected, $Actual, [string]$Message) if ((ConvertTo-AriaJson -Value ([pscustomobject][ordered]@{v=$Expected})) -ne (ConvertTo-AriaJson -Value ([pscustomobject][ordered]@{v=$Actual}))) { throw "$Message Expected=$Expected Actual=$Actual" } }

$policy = Join-Path $root 'aria.policy.json'
$hello = Join-Path $root 'examples/hello.aria'
$denied = Join-Path $root 'examples/denied-write.aria'

Test-Case 'opcode registry is machine-readable and complete' {
    $registry = Get-AriaOpcodeRegistry
    Assert-Equal 37 $registry.Count 'Opcode registry size mismatch.'
    Assert-Equal 1 $registry['EMIT'].pops 'EMIT stack contract mismatch.'
}

Test-Case 'glyph registry is machine-readable and unique' {
    $registry = Get-AriaGlyphRegistry
    Assert-Equal '⟁' $registry['agent'] 'Agent glyph mismatch.'
    Assert-Equal 10 $registry.Count 'Glyph registry size mismatch.'
}

Test-Case 'parser recognizes program and glyph graph' {
    $parsed = Parse-AriaSource -Source (Get-AriaSourceText -Path $hello) -SourceName $hello
    Assert-Equal 'HelloARIA' $parsed.model.programName 'Program name mismatch.'
    Assert-Equal 4 $parsed.model.graphs[0].nodes.Count 'Graph node count mismatch.'
    Assert-Equal 0 (Get-AriaErrorDiagnostics -Diagnostics $parsed.diagnostics).Count 'Parser emitted errors.'
}

Test-Case 'compiler output is deterministic' {
    $gate = Invoke-AriaGate -SourcePath $hello -PolicyPath $policy -WorkspaceRoot $root -Quiet
    $one = Get-AriaSha256Bytes -Bytes $gate.bytes
    $two = Get-AriaSha256Bytes -Bytes (ConvertTo-AriaContainerBytes -BytecodeModel $gate.bytecode)
    Assert-Equal $one $two 'Container hashes differ.'
}

Test-Case 'container round-trip verifies digest' {
    $gate = Invoke-AriaGate -SourcePath $hello -PolicyPath $policy -WorkspaceRoot $root -Quiet
    $container = Read-AriaContainerBytes -Bytes $gate.bytes
    Assert-Equal 'HelloARIA' $container.bytecode.programName 'Round-trip program mismatch.'
}

Test-Case 'VM executes output and memory' {
    $gate = Invoke-AriaGate -SourcePath $hello -PolicyPath $policy -WorkspaceRoot $root -Quiet
    $container = Read-AriaContainerBytes -Bytes $gate.bytes
    $result = Invoke-AriaContainer -Container $container -PolicyPath $policy -WorkspaceRoot $root -PassThru
    Assert-Equal 'ARIA is online.' $result.outputs[0] 'First output mismatch.'
    Assert-Equal 'active' $result.outputs[1] 'Memory output mismatch.'
}


Test-Case 'bytecode verifier accepts compiler output' {
    $gate = Invoke-AriaGate -SourcePath $hello -PolicyPath $policy -WorkspaceRoot $root -Quiet
    $verification = Test-AriaBytecodeModel -BytecodeModel $gate.bytecode
    Assert-True $verification.valid ('Verifier rejected compiler output: ' + ($verification.errors -join '; '))
    Assert-True ($verification.maxStack -ge 1) 'Verifier did not calculate stack depth.'
}

Test-Case 'bytecode verifier rejects stack underflow' {
    $gate = Invoke-AriaGate -SourcePath $hello -PolicyPath $policy -WorkspaceRoot $root -Quiet
    $malicious = $gate.bytecode | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $malicious.instructions = @(
        [pscustomobject][ordered]@{ op = 'EMIT'; line = 1 },
        [pscustomobject][ordered]@{ op = 'HALT'; line = 2 }
    )
    $verification = Test-AriaBytecodeModel -BytecodeModel $malicious
    Assert-True (-not $verification.valid) 'Stack-underflow bytecode unexpectedly passed verification.'
}

Test-Case 'container corruption is detected' {
    $gate = Invoke-AriaGate -SourcePath $hello -PolicyPath $policy -WorkspaceRoot $root -Quiet
    [byte[]]$corrupt = $gate.bytes.Clone()
    $corrupt[$corrupt.Length - 1] = $corrupt[$corrupt.Length - 1] -bxor 1
    $rejected = $false
    try { $null = Read-AriaContainerBytes -Bytes $corrupt }
    catch { $rejected = $true }
    Assert-True $rejected 'Corrupted container unexpectedly passed verification.'
}

Test-Case 'locked spec rejects incompatible source' {
    $temp = Join-Path $env:TEMP ('aria-spec-' + [guid]::NewGuid().ToString('N') + '.aria')
    try {
        Write-AriaUtf8NoBom -Path $temp -Text @'
aria 9.9.9
program Future version 0.1.0
entry Main
flow Main {
  emit "future"
}
'@
        $rejected = $false
        try { $null = Invoke-AriaGate -SourcePath $temp -PolicyPath $policy -WorkspaceRoot $root -Quiet }
        catch { $rejected = $true }
        Assert-True $rejected 'Incompatible language spec unexpectedly passed.'
    }
    finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

Test-Case 'default policy rejects filesystem writes' {
    $rejected = $false
    try { $null = Invoke-AriaGate -SourcePath $denied -PolicyPath $policy -WorkspaceRoot $root -Quiet }
    catch { $rejected = $true }
    Assert-True $rejected 'Denied write program unexpectedly passed.'
}

Test-Case 'path confinement rejects traversal' {
    $rejected = $false
    try { $null = Resolve-AriaConfinedPath -WorkspaceRoot $root -Scope '.' -RequestedPath '../outside.txt' }
    catch { $rejected = $true }
    Assert-True $rejected 'Traversal path unexpectedly passed.'
}


Test-Case 'repository manifest verifies' {
    $manifest = Test-AriaManifest -Root $root
    Assert-True $manifest.valid ("Manifest verification failed: $($manifest.message)")
}


Test-Case 'strict repository manifest gate accepts tracked tree' {
    $gate = Invoke-AriaGate -SourcePath $hello -PolicyPath $policy -WorkspaceRoot $root -Quiet -StrictRepository
    Assert-Equal 'HelloARIA' $gate.bytecode.programName 'Strict gate program mismatch.'
}

Test-Case 'VM rejects structurally invalid but checksummed bytecode' {
    $gate = Invoke-AriaGate -SourcePath $hello -PolicyPath $policy -WorkspaceRoot $root -Quiet
    $mutated = Read-AriaContainerBytes -Bytes $gate.bytes
    $mutated.bytecode.instructions[0].op = 'UNKNOWN_OPCODE'
    $repacked = Read-AriaContainerBytes -Bytes (ConvertTo-AriaContainerBytes -BytecodeModel $mutated.bytecode)
    $rejected = $false
    try { $null = Invoke-AriaContainer -Container $repacked -PolicyPath $policy -WorkspaceRoot $root -PassThru }
    catch { $rejected = $true }
    Assert-True $rejected 'VM executed invalid bytecode with a valid container digest.'
}

Test-Case 'container rejects header length mismatch' {
    $gate = Invoke-AriaGate -SourcePath $hello -PolicyPath $policy -WorkspaceRoot $root -Quiet
    $tampered = New-Object byte[] $gate.bytes.Length
    [Array]::Copy($gate.bytes, $tampered, $gate.bytes.Length)
    $tampered[12] = [byte]($tampered[12] -bxor 1)
    $rejected = $false
    try { $null = Read-AriaContainerBytes -Bytes $tampered }
    catch { $rejected = $true }
    Assert-True $rejected 'Container with a mismatched payload length unexpectedly passed.'
}


Test-Case 'custom workspace receives build and memory state' {
    $workspace = Join-Path $env:TEMP ('aria-workspace-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $workspace -Force | Out-Null
        $compiled = Invoke-AriaCompile -SourcePath $hello -PolicyPath $policy -WorkspaceRoot $workspace -Quiet
        Assert-True ($compiled.artifactPath.StartsWith([System.IO.Path]::GetFullPath($workspace), [System.StringComparison]::OrdinalIgnoreCase)) 'Artifact was not rooted in the selected workspace.'
        $container = Read-AriaContainer -Path $compiled.artifactPath
        $result = Invoke-AriaContainer -Container $container -PolicyPath $policy -WorkspaceRoot $workspace -PassThru
        Assert-True (Test-Path -LiteralPath $result.statePath) 'Memory state was not written to the selected workspace.'
    }
    finally { Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue }
}

Test-Case 'glyph mismatch is rejected semantically' {
    $temp = Join-Path $env:TEMP ('aria-glyph-' + [guid]::NewGuid().ToString('N') + '.aria')
    try {
        Write-AriaUtf8NoBom -Path $temp -Text @'
aria 0.4.0
program WrongGlyph version 0.1.0
entry Main
graph Invalid {
  node ◉ agent architect
}
flow Main {
  halt
}
'@
        $rejected = $false
        try { $null = Invoke-AriaGate -SourcePath $temp -PolicyPath $policy -WorkspaceRoot $root -Quiet }
        catch { $rejected = $true }
        Assert-True $rejected 'Mismatched glyph and node kind unexpectedly passed.'
    }
    finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

Test-Case 'runtime rechecks capability policy' {
    $workspace = Join-Path $env:TEMP ('aria-runtime-policy-' + [guid]::NewGuid().ToString('N'))
    $denyPolicy = Join-Path $workspace 'deny.policy.json'
    try {
        New-Item -ItemType Directory -Path $workspace -Force | Out-Null
        Write-AriaUtf8NoBom -Path (Join-Path $workspace 'README.md') -Text "runtime policy fixture`n"
        $compiled = Invoke-AriaCompile -SourcePath (Join-Path $root 'examples/read-repository.aria') -PolicyPath $policy -WorkspaceRoot $workspace -Quiet
        $policyDocument = Get-AriaPolicy -PolicyPath $policy
        $policyDocument.effects.'fs.read'.allow = $false
        Write-AriaUtf8NoBom -Path $denyPolicy -Text (($policyDocument | ConvertTo-Json -Depth 20) + "`n")
        $rejected = $false
        try { $null = Invoke-AriaArtifact -Path $compiled.artifactPath -PolicyPath $denyPolicy -WorkspaceRoot $workspace -PassThru }
        catch { $rejected = $true }
        Assert-True $rejected 'Runtime executed a capability denied by the execution-time policy.'
    }
    finally { Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue }
}

Test-Case 'read-only execution does not persist memory state' {
    $workspace = Join-Path $env:TEMP ('aria-readonly-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $workspace -Force | Out-Null
        Write-AriaUtf8NoBom -Path (Join-Path $workspace 'README.md') -Text "read-only fixture`n"
        $compiled = Invoke-AriaCompile -SourcePath (Join-Path $root 'examples/read-repository.aria') -PolicyPath $policy -WorkspaceRoot $workspace -Quiet
        $result = Invoke-AriaArtifact -Path $compiled.artifactPath -PolicyPath $policy -WorkspaceRoot $workspace -PassThru
        Assert-Equal 'read-only fixture' ([string]$result.outputs[0]).Trim() 'Repository read output mismatch.'
        Assert-True (-not $result.memoryPersisted) 'Read-only program reported memory persistence.'
        Assert-True (-not (Test-Path -LiteralPath $result.statePath)) 'Read-only program created a memory state file.'
    }
    finally { Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue }
}


Test-Case 'parser recognizes structured signals' {
    $source = @'
aria 0.4.0
program SignalProbe version 0.1.0
entry Main
flow Main {
  signal pulse "compiler awake"
  signal pass "compiler ready"
}
'@
    $parsed = Parse-AriaSource -Source $source -SourceName '<signal-probe>'
    Assert-Equal 0 (Get-AriaErrorDiagnostics -Diagnostics $parsed.diagnostics).Count 'Signal parser emitted errors.'
    Assert-Equal 'signal' $parsed.model.flows[0].statements[0].op 'Signal opcode was not parsed.'
    Assert-Equal 'pulse' $parsed.model.flows[0].statements[0].state 'Signal state mismatch.'
}

Test-Case 'VM emits structured traceflow events' {
    $gate = Invoke-AriaGate -SourcePath $hello -PolicyPath $policy -WorkspaceRoot $root -Quiet
    $container = Read-AriaContainerBytes -Bytes $gate.bytes
    $result = Invoke-AriaContainer -Container $container -PolicyPath $policy -WorkspaceRoot $root -PassThru
    Assert-True ($result.events.Count -ge 2) 'Traceflow events were not produced.'
    Assert-Equal 'pulse' $result.events[0].state 'First traceflow state mismatch.'
    Assert-Equal 'language core' $result.events[0].text 'First traceflow text mismatch.'
}

Test-Case 'canonical JSON is stable and preserves glyphs' {
    $value = [pscustomobject][ordered]@{
        z = 1
        glyph = '⟁'
        nested = [pscustomobject][ordered]@{ enabled = $true; empty = $null }
    }
    $json = ConvertTo-AriaJson -Value $value
    Assert-Equal '{"z":1,"glyph":"⟁","nested":{"enabled":true,"empty":null}}' $json 'Canonical JSON mismatch.'
    $roundTrip = $json | ConvertFrom-Json
    Assert-Equal '⟁' $roundTrip.glyph 'Canonical JSON glyph round-trip failed.'
}



Test-Case 'parser recognizes module functions and typed expressions' {
    $source = Get-AriaSourceText -Path (Join-Path $root 'examples/functions.aria')
    $parsed = Parse-AriaSource -Source $source -SourceName '<functions>'
    Assert-Equal 0 (Get-AriaErrorDiagnostics -Diagnostics $parsed.diagnostics).Count 'Typed parser emitted errors.'
    Assert-Equal 'Arithmetic' $parsed.model.moduleName 'Module name mismatch.'
    Assert-Equal 2 $parsed.model.functions.Count 'Function count mismatch.'
    Assert-Equal 'call' $parsed.model.flows[0].statements[0].expression.kind 'Function call expression was not parsed.'
}

Test-Case 'functions execute with typed returns' {
    $compiled = Invoke-AriaCompile -SourcePath (Join-Path $root 'examples/functions.aria') -PolicyPath $policy -WorkspaceRoot $root -Quiet
    $result = Invoke-AriaArtifact -Path $compiled.artifactPath -PolicyPath $policy -WorkspaceRoot $root -PassThru
    Assert-Equal '5' $result.outputs[0] 'Function result output mismatch.'
    Assert-Equal 'high' $result.outputs[1] 'Conditional function output mismatch.'
}

Test-Case 'bounded repeat and lexical set execute' {
    $compiled = Invoke-AriaCompile -SourcePath (Join-Path $root 'examples/control-flow.aria') -PolicyPath $policy -WorkspaceRoot $root -Quiet
    $result = Invoke-AriaArtifact -Path $compiled.artifactPath -PolicyPath $policy -WorkspaceRoot $root -PassThru
    Assert-Equal '6' $result.outputs[0] 'Repeat accumulation mismatch.'
    Assert-Equal 'pass' $result.events[0].state 'Conditional trace state mismatch.'
}

Test-Case 'agent dispatch emits deterministic event' {
    $compiled = Invoke-AriaCompile -SourcePath (Join-Path $root 'examples/agent-dispatch.aria') -PolicyPath $policy -WorkspaceRoot $root -Quiet
    $result = Invoke-AriaArtifact -Path $compiled.artifactPath -PolicyPath $policy -WorkspaceRoot $root -PassThru
    Assert-Equal 'agent' $result.events[0].kind 'Agent event kind mismatch.'
    Assert-Equal 'Architect' $result.events[0].agent 'Agent dispatch target mismatch.'
    Assert-Equal 'analyze repository graph' $result.events[0].text 'Agent dispatch task mismatch.'
}

Test-Case 'typed binding rejects incompatible value' {
    $temp = Join-Path $env:TEMP ('aria-type-' + [guid]::NewGuid().ToString('N') + '.aria')
    try {
        Write-AriaUtf8NoBom -Path $temp -Text @'
aria 0.4.0
program WrongType version 0.1.0
entry Main
flow Main {
  let count: Number = "three"
  halt
}
'@
        $rejected = $false
        try { $null = Invoke-AriaGate -SourcePath $temp -PolicyPath $policy -WorkspaceRoot $root -Quiet }
        catch { $rejected = $true }
        Assert-True $rejected 'Incompatible typed binding unexpectedly passed.'
    }
    finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

Test-Case 'repeat rejects unsafe literal bound' {
    $temp = Join-Path $env:TEMP ('aria-repeat-' + [guid]::NewGuid().ToString('N') + '.aria')
    try {
        Write-AriaUtf8NoBom -Path $temp -Text @'
aria 0.4.0
program UnsafeLoop version 0.1.0
entry Main
flow Main {
  repeat 10001 as index {
    emit index
  }
  halt
}
'@
        $rejected = $false
        try { $null = Invoke-AriaGate -SourcePath $temp -PolicyPath $policy -WorkspaceRoot $root -Quiet }
        catch { $rejected = $true }
        Assert-True $rejected 'Unsafe repeat bound unexpectedly passed.'
    }
    finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

Test-Case 'module identity survives bytecode container' {
    $gate = Invoke-AriaGate -SourcePath (Join-Path $root 'examples/functions.aria') -PolicyPath $policy -WorkspaceRoot $root -Quiet
    $container = Read-AriaContainerBytes -Bytes $gate.bytes
    Assert-Equal 'Arithmetic' $container.bytecode.moduleName 'Module name did not survive compilation.'
    Assert-Equal '0.1.0' $container.bytecode.moduleVersion 'Module version did not survive compilation.'
}

Test-Case 'persisted memory type is revalidated' {
    $workspace = Join-Path $env:TEMP ('aria-memory-type-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path (Join-Path $workspace '.aria/state') -Force | Out-Null
        $compiled = Invoke-AriaCompile -SourcePath (Join-Path $root 'examples/coreflow.aria') -PolicyPath $policy -WorkspaceRoot $workspace -Quiet
        Write-AriaUtf8NoBom -Path (Join-Path $workspace '.aria/state/CoreflowDemo.memory.json') -Text '{"Runtime":{"cycles":"wrong","status":"ready"}}'
        $rejected = $false
        try { $null = Invoke-AriaArtifact -Path $compiled.artifactPath -PolicyPath $policy -WorkspaceRoot $workspace -PassThru }
        catch { $rejected = $true }
        Assert-True $rejected 'Invalid persisted memory type unexpectedly executed.'
    }
    finally { Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue }
}



Test-Case 'bytecode verifier rejects arithmetic type confusion' {
    $gate = Invoke-AriaGate -SourcePath (Join-Path $root 'examples/functions.aria') -PolicyPath $policy -WorkspaceRoot $root -Quiet
    $mutated = $gate.bytecode | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $mutated.instructions = @(
        [pscustomobject][ordered]@{ op = 'PUSH_CONST'; arg = 0; type = 'Text'; line = 1 },
        [pscustomobject][ordered]@{ op = 'PUSH_CONST'; arg = 1; type = 'Number'; line = 1 },
        [pscustomobject][ordered]@{ op = 'ADD'; line = 1 },
        [pscustomobject][ordered]@{ op = 'EMIT'; line = 1 },
        [pscustomobject][ordered]@{ op = 'HALT'; line = 2 }
    )
    $mutated.constants = @('text', 1)
    $verification = Test-AriaBytecodeModel -BytecodeModel $mutated
    Assert-True (-not $verification.valid) 'Mixed Text+Number ADD unexpectedly passed verification.'
}

Test-Case 'bytecode verifier rejects non-text agent task' {
    $gate = Invoke-AriaGate -SourcePath (Join-Path $root 'examples/agent-dispatch.aria') -PolicyPath $policy -WorkspaceRoot $root -Quiet
    $mutated = $gate.bytecode | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $mutated.constants = @(42)
    $mutated.instructions = @(
        [pscustomobject][ordered]@{ op = 'PUSH_CONST'; arg = 0; type = 'Number'; line = 1 },
        [pscustomobject][ordered]@{ op = 'AGENT_DISPATCH'; agent = 'Architect'; line = 1 },
        [pscustomobject][ordered]@{ op = 'HALT'; line = 2 }
    )
    $verification = Test-AriaBytecodeModel -BytecodeModel $mutated
    Assert-True (-not $verification.valid) 'Numeric agent task unexpectedly passed verification.'
}

Test-Case 'Null-returning function remains a typed expression' {
    $temp = Join-Path $env:TEMP ('aria-null-call-' + [guid]::NewGuid().ToString('N') + '.aria')
    try {
        Write-AriaUtf8NoBom -Path $temp -Text @'
aria 0.4.0
module NullCalls version 0.1.0
program NullCall version 0.1.0
entry Main
function Nothing() -> Null {
  return
}
flow Main {
  let result: Null = Nothing()
  assert result == null
  halt
}
'@
        $compiled = Invoke-AriaCompile -SourcePath $temp -PolicyPath $policy -WorkspaceRoot $root -Quiet
        $result = Invoke-AriaArtifact -Path $compiled.artifactPath -PolicyPath $policy -WorkspaceRoot $root -PassThru
        Assert-True ($null -eq $result.variables.result) 'Null function result was not retained as a typed value.'
    }
    finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}


Test-Case 'parser recognizes connection ontology and lifecycle' {
    $source = Get-AriaSourceText -Path (Join-Path $root 'examples/connection.aria')
    $parsed = Parse-AriaSource -Source $source -SourceName '<connection>'
    Assert-Equal 0 (Get-AriaErrorDiagnostics -Diagnostics $parsed.diagnostics).Count 'Connection parser emitted errors.'
    Assert-Equal 1 $parsed.model.connections.Count 'Connection declaration count mismatch.'
    Assert-Equal 'HumanAI' $parsed.model.connections[0].name 'Connection name mismatch.'
    Assert-Equal 'connect' $parsed.model.flows[0].statements[0].op 'Connection open statement mismatch.'
    Assert-Equal 'consent' $parsed.model.flows[0].statements[3].op 'Connection consent statement mismatch.'
}

Test-Case 'connection ontology survives bytecode container' {
    $gate = Invoke-AriaGate -SourcePath (Join-Path $root 'examples/connection.aria') -PolicyPath $policy -WorkspaceRoot $root -Quiet
    $container = Read-AriaContainerBytes -Bytes $gate.bytes
    Assert-Equal 1 $container.bytecode.connections.Count 'Connection declaration did not survive compilation.'
    Assert-Equal 'intent-proposal-consent' $container.bytecode.connections[0].protocol 'Connection protocol mismatch.'
}

Test-Case 'VM emits deterministic connection lifecycle' {
    $compiled = Invoke-AriaCompile -SourcePath (Join-Path $root 'examples/connection.aria') -PolicyPath $policy -WorkspaceRoot $root -Quiet
    $result = Invoke-AriaArtifact -Path $compiled.artifactPath -PolicyPath $policy -WorkspaceRoot $root -PassThru
    $events = @($result.events | Where-Object { $_.kind -eq 'connection' })
    Assert-Equal 5 $events.Count 'Connection event count mismatch.'
    Assert-Equal 'open' $events[0].state 'Connection open event mismatch.'
    Assert-Equal 'intent' $events[1].state 'Connection intent event mismatch.'
    Assert-Equal 'proposal' $events[2].state 'Connection proposal event mismatch.'
    Assert-Equal $true $events[3].approved 'Connection consent was not recorded.'
    Assert-Equal 'closed' $events[4].state 'Connection close event mismatch.'
}

Test-Case 'withheld consent closes without authority' {
    $temp = Join-Path $env:TEMP ('aria-consent-' + [guid]::NewGuid().ToString('N') + '.aria')
    try {
        Write-AriaUtf8NoBom -Path $temp -Text @'
aria 0.4.0
program WithheldConsent version 0.1.0
entry Main
agent Architect {
}
connection HumanAI {
  operator = "human"
  agent = "Architect"
  protocol = "intent-proposal-consent"
}
flow Main {
  connect HumanAI
  intent HumanAI <- "inspect"
  propose HumanAI <- "change"
  consent HumanAI <- false
  disconnect HumanAI
  halt
}
'@
        $compiled = Invoke-AriaCompile -SourcePath $temp -PolicyPath $policy -WorkspaceRoot $root -Quiet
        $result = Invoke-AriaArtifact -Path $compiled.artifactPath -PolicyPath $policy -WorkspaceRoot $root -PassThru
        $consent = @($result.events | Where-Object { $_.kind -eq 'connection' -and $_.state -eq 'consent' })[0]
        Assert-Equal $false $consent.approved 'Withheld consent was not preserved.'
        Assert-Equal 'closed' $result.connections['HumanAI'].phase 'Withheld connection did not close safely.'
    }
    finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

Test-Case 'semantics rejects unknown connection' {
    $temp = Join-Path $env:TEMP ('aria-unknown-connection-' + [guid]::NewGuid().ToString('N') + '.aria')
    try {
        Write-AriaUtf8NoBom -Path $temp -Text @'
aria 0.4.0
program UnknownConnection version 0.1.0
entry Main
flow Main {
  connect Missing
  halt
}
'@
        $rejected = $false
        try { $null = Invoke-AriaGate -SourcePath $temp -PolicyPath $policy -WorkspaceRoot $root -Quiet }
        catch { $rejected = $true }
        Assert-True $rejected 'Unknown connection unexpectedly passed.'
    }
    finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

Test-Case 'connection rejects unknown agent identity' {
    $temp = Join-Path $env:TEMP ('aria-unknown-agent-connection-' + [guid]::NewGuid().ToString('N') + '.aria')
    try {
        Write-AriaUtf8NoBom -Path $temp -Text @'
aria 0.4.0
program UnknownConnectionAgent version 0.1.0
entry Main
connection HumanAI {
  operator = "human"
  agent = "Missing"
  protocol = "intent-proposal-consent"
}
flow Main {
  halt
}
'@
        $rejected = $false
        try { $null = Invoke-AriaGate -SourcePath $temp -PolicyPath $policy -WorkspaceRoot $root -Quiet }
        catch { $rejected = $true }
        Assert-True $rejected 'Connection with unknown agent unexpectedly passed.'
    }
    finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

Test-Case 'bytecode verifier rejects non-text connection intent' {
    $gate = Invoke-AriaGate -SourcePath (Join-Path $root 'examples/connection.aria') -PolicyPath $policy -WorkspaceRoot $root -Quiet
    $mutated = $gate.bytecode | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $mutated.constants = @(42)
    $mutated.instructions = @(
        [pscustomobject][ordered]@{ op = 'PUSH_CONST'; arg = 0; type = 'Number'; line = 1 },
        [pscustomobject][ordered]@{ op = 'CONNECT_INTENT'; connection = 'HumanAI'; line = 1 },
        [pscustomobject][ordered]@{ op = 'HALT'; line = 2 }
    )
    $verification = Test-AriaBytecodeModel -BytecodeModel $mutated
    Assert-True (-not $verification.valid) 'Numeric connection intent unexpectedly passed verification.'
}

Test-Case 'VM rejects connection message before open' {
    $gate = Invoke-AriaGate -SourcePath (Join-Path $root 'examples/connection.aria') -PolicyPath $policy -WorkspaceRoot $root -Quiet
    $mutated = $gate.bytecode | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $mutated.constants = @('premature')
    $mutated.instructions = @(
        [pscustomobject][ordered]@{ op = 'PUSH_CONST'; arg = 0; type = 'Text'; line = 1 },
        [pscustomobject][ordered]@{ op = 'CONNECT_INTENT'; connection = 'HumanAI'; line = 1 },
        [pscustomobject][ordered]@{ op = 'HALT'; line = 2 }
    )
    $container = Read-AriaContainerBytes -Bytes (ConvertTo-AriaContainerBytes -BytecodeModel $mutated)
    $rejected = $false
    try { $null = Invoke-AriaContainer -Container $container -PolicyPath $policy -WorkspaceRoot $root -PassThru }
    catch { $rejected = $true }
    Assert-True $rejected 'Connection intent before open unexpectedly executed.'
}

$script:SuiteClock.Stop()
Write-AriaSummary -Title 'CONFORMANCE COMPLETE' -Passed ($script:Failed -eq 0) -Detail ("{0} passed · {1} failed" -f $script:Passed, $script:Failed) -Duration $script:SuiteClock.Elapsed
if ($script:Failed -gt 0) { throw "ARIA test suite failed: $script:Failed failure(s)." }
