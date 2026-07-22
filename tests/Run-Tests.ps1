[CmdletBinding()]
param([switch]$VerboseOutput)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tempRoot = [System.IO.Path]::GetTempPath()
if ([string]::IsNullOrWhiteSpace($tempRoot)) {
    throw 'ARIA could not resolve the platform temporary directory.'
}

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

$script:Passed = 0
$script:Failed = 0
$script:SuiteClock = [Diagnostics.Stopwatch]::StartNew()
Write-AriaBanner -Title 'ARIA / CONFORMANCE' -Subtitle 'compiler · verifier · policy · memory · virtual machine'
Start-AriaEnumerator -Name 'conformance lattice' -Expected 105 -Domain 'conformance'
function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        & $Body
        $clock.Stop()
        Add-AriaEnumerationItem -Name $Name -State Pass -Duration $clock.Elapsed
        $script:Passed++
    }
    catch {
        $clock.Stop()
        Add-AriaEnumerationItem -Name $Name -State Fail -Detail $_.Exception.Message -Duration $clock.Elapsed
        if ($VerboseOutput) { Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray }
        $script:Failed++
    }
}
function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Assert-Equal { param($Expected, $Actual, [string]$Message) if ((ConvertTo-AriaJson -Value ([pscustomobject][ordered]@{v=$Expected})) -ne (ConvertTo-AriaJson -Value ([pscustomobject][ordered]@{v=$Actual}))) { throw "$Message Expected=$Expected Actual=$Actual" } }

$policy = Join-Path $root 'aria.policy.json'
$hello = Join-Path $root 'examples/hello.aria'
$denied = Join-Path $root 'examples/denied-write.aria'


Import-Module (Join-Path $root 'src/Aria.GraphCore.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.TypedCore.psm1') -Force -DisableNameChecking

Import-Module (Join-Path $root 'src/Aria.GraphReplay.psm1') -Force -DisableNameChecking

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
    $temp = Join-Path $tempRoot ('aria-spec-' + [guid]::NewGuid().ToString('N') + '.aria')
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
    $workspace = Join-Path $tempRoot ('aria-workspace-' + [guid]::NewGuid().ToString('N'))
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
    $temp = Join-Path $tempRoot ('aria-glyph-' + [guid]::NewGuid().ToString('N') + '.aria')
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
    $workspace = Join-Path $tempRoot ('aria-runtime-policy-' + [guid]::NewGuid().ToString('N'))
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
    $workspace = Join-Path $tempRoot ('aria-readonly-' + [guid]::NewGuid().ToString('N'))
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
    $temp = Join-Path $tempRoot ('aria-type-' + [guid]::NewGuid().ToString('N') + '.aria')
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
    $temp = Join-Path $tempRoot ('aria-repeat-' + [guid]::NewGuid().ToString('N') + '.aria')
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
    $workspace = Join-Path $tempRoot ('aria-memory-type-' + [guid]::NewGuid().ToString('N'))
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
    $temp = Join-Path $tempRoot ('aria-null-call-' + [guid]::NewGuid().ToString('N') + '.aria')
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
    $temp = Join-Path $tempRoot ('aria-consent-' + [guid]::NewGuid().ToString('N') + '.aria')
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
    $temp = Join-Path $tempRoot ('aria-unknown-connection-' + [guid]::NewGuid().ToString('N') + '.aria')
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
    $temp = Join-Path $tempRoot ('aria-unknown-agent-connection-' + [guid]::NewGuid().ToString('N') + '.aria')
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

Test-Case 'runtime profile resolves CI deterministically' {
    $beforeCI = $env:CI
    $beforeOutput = $env:ARIA_OUTPUT
    try {
        $env:CI = 'true'
        $env:ARIA_OUTPUT = ''
        $profile = Get-AriaRuntimeProfile
        Assert-Equal 'ci' $profile.mode 'CI profile mismatch.'
        Assert-True (-not $profile.animation) 'CI profile unexpectedly enables animation.'
    }
    finally {
        $env:CI = $beforeCI
        $env:ARIA_OUTPUT = $beforeOutput
    }
}

Test-Case 'transmission canonical digest is deterministic' {
    $payload = [pscustomobject][ordered]@{ repository='ARIA'; checks=@('pass','pass','pass') }
    $one = New-AriaTransmission -Channel github -Kind workflow -Status pass -Source test -Payload $payload
    $two = New-AriaTransmission -Channel github -Kind workflow -Status pass -Source test -Payload $payload
    Assert-Equal $one.digest $two.digest 'Transmission digest changed for identical content.'
}

Test-Case 'compressed transmission round-trip verifies' {
    $record = New-AriaTransmission -Channel github -Kind workflow -Status pass -Source test -Payload ([pscustomobject][ordered]@{run=7; conclusion='success'})
    [byte[]]$bytes = ConvertTo-AriaTransmissionBytes -Transmission $record
    $decoded = Read-AriaTransmissionBytes -Bytes $bytes
    Assert-Equal $record.digest $decoded.digest 'Transmission round-trip digest mismatch.'
    Assert-Equal 'github' $decoded.channel 'Transmission round-trip channel mismatch.'
}

Test-Case 'transmission container rejects tampering' {
    $record = New-AriaTransmission -Channel github -Kind workflow -Status pass -Source test -Payload ([pscustomobject][ordered]@{run=7})
    [byte[]]$bytes = ConvertTo-AriaTransmissionBytes -Transmission $record
    $bytes[$bytes.Length-1] = $bytes[$bytes.Length-1] -bxor 1
    $rejected = $false
    try { $null = Read-AriaTransmissionBytes -Bytes $bytes } catch { $rejected = $true }
    Assert-True $rejected 'Tampered transmission unexpectedly passed verification.'
}
Test-Case 'event digest is deterministic for fixed time' {
    $null = Initialize-AriaEventSpine -WorkspaceRoot $root -Profile compact
    $time = [datetime]'2026-01-01T00:00:00Z'
    $one = New-AriaEvent -Domain runtime -Phase probe -State PASS -Energy verify -Information stable -Coherence sealed -OccurredAt $time
    $null = Initialize-AriaEventSpine -WorkspaceRoot $root -Profile compact
    $two = New-AriaEvent -Domain runtime -Phase probe -State PASS -Energy verify -Information stable -Coherence sealed -OccurredAt $time
    Assert-Equal $one.digest $two.digest 'Event digest changed for identical content.'
}

Test-Case 'event spine publishes to subscriber and buffer' {
    $null = Initialize-AriaEventSpine -WorkspaceRoot $root -Profile compact
    $script:ObservedEvent = $null
    $null = Register-AriaEventSubscriber -Handler { param($event) $script:ObservedEvent = $event }
    $published = Send-AriaEvent -Domain runtime -Phase subscriber -State PASS -Energy dispatch -Information event -Coherence observed -PassThru
    Assert-Equal $published.digest $script:ObservedEvent.digest 'Subscriber did not receive published event.'
    Assert-Equal 1 @(Get-AriaEventBuffer).Count 'Event buffer count mismatch.'
}

Test-Case 'event verifier rejects tampering' {
    $null = Initialize-AriaEventSpine -WorkspaceRoot $root -Profile compact
    $event = New-AriaEvent -Domain runtime -Phase tamper -State PASS -Energy verify -Information original -Coherence sealed
    $event.information = 'mutated'
    $verification = Test-AriaEvent -Event $event
    Assert-True (-not $verification.valid) 'Tampered event unexpectedly passed.'
}

Test-Case 'event ledger persists and replays verified events' {
    $workspace = Join-Path $tempRoot ('aria-event-ledger-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $workspace -Force | Out-Null
        $null = Initialize-AriaEventSpine -WorkspaceRoot $workspace -Profile compact -Persist
        $null = Send-AriaEvent -Domain transmission -Phase replay -State PASS -Energy persist -Information ledger -Coherence verified
        $events = @(Read-AriaEventLedger -WorkspaceRoot $workspace)
        Assert-Equal 1 $events.Count 'Event ledger replay count mismatch.'
        Assert-Equal 'transmission' $events[0].domain 'Event ledger domain mismatch.'
    }
    finally { Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue }
}
Test-Case 'runtime spine maps compiler event to Etherflow' {
    $null = Initialize-AriaEventSpine -WorkspaceRoot $root -Profile compact
    $event = New-AriaEvent -Domain compiler -Phase compile -State ACTIVE -Energy translation -Information hello.aria -Coherence engaged
    $ether = ConvertTo-AriaEtherEvent -Event $event
    Assert-Equal 'compiler.compile' $ether.phase 'Compiler event phase mismatch.'
    Assert-Equal 'translation' $ether.energy 'Compiler energy mismatch.'
}

Test-Case 'runtime spine preserves verifier authority boundary' {
    $null = Initialize-AriaEventSpine -WorkspaceRoot $root -Profile compact
    $event = New-AriaEvent -Domain verifier -Phase artifact -State PASS -Energy verification -Information hello.ariac -Coherence accepted
    $verification = Test-AriaEvent -Event $event
    Assert-True $verification.valid 'Verifier event failed event verification.'
    Assert-Equal 'verifier' $event.domain 'Verifier domain mismatch.'
}

Test-Case 'runtime spine records VM activation and halt order' {
    $null = Initialize-AriaEventSpine -WorkspaceRoot $root -Profile compact
    $null = Send-AriaEvent -Domain vm -Phase execute -State ACTIVE -Energy execution -Information HelloARIA -Coherence active
    $null = Send-AriaEvent -Domain vm -Phase halt -State PASS -Energy completion -Information HelloARIA -Coherence halted
    $events = @(Get-AriaEventBuffer)
    Assert-Equal 2 $events.Count 'VM event count mismatch.'
    Assert-Equal 'execute' $events[0].phase 'VM activation order mismatch.'
    Assert-Equal 'halt' $events[1].phase 'VM halt order mismatch.'
}

Test-Case 'runtime spine connection lifecycle is ordered' {
    $null = Initialize-AriaEventSpine -WorkspaceRoot $root -Profile compact
    foreach($phase in @('intent','proposal','consent','closure')){
        $null = Send-AriaEvent -Domain connection -Phase $phase -State PASS -Energy lifecycle -Information $phase -Coherence verified
    }
    $events = @(Get-AriaEventBuffer)
    Assert-Equal 'intent' $events[0].phase 'Connection intent order mismatch.'
    Assert-Equal 'proposal' $events[1].phase 'Connection proposal order mismatch.'
    Assert-Equal 'consent' $events[2].phase 'Connection consent order mismatch.'
    Assert-Equal 'closure' $events[3].phase 'Connection closure order mismatch.'
}
Test-Case 'event digest survives JSON date materialization' {
    $null = Initialize-AriaEventSpine -WorkspaceRoot $root -Profile compact
    $event = New-AriaEvent `
        -Domain runtime `
        -Phase portability `
        -State PASS `
        -Energy verification `
        -Information timestamp `
        -Coherence invariant `
        -OccurredAt ([datetime]'2026-01-01T00:00:00Z')

    $reloaded = $event | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $verification = Test-AriaEvent -Event $reloaded
    Assert-True $verification.valid 'Event digest changed after JSON date materialization.'
}
Test-Case 'gitflow process captures native output' {
    $result = Invoke-AriaGitProcess -Arguments @('--version') -RepositoryRoot $root
    Assert-Equal 0 $result.exitCode 'Git version command failed.'
    Assert-True ($result.stdout -match '^git version') 'Git output was not captured.'
}

Test-Case 'gitflow resolves local head deterministically' {
    $one = Get-AriaGitHead -RepositoryRoot $root
    $two = Get-AriaGitHead -RepositoryRoot $root
    Assert-Equal $one $two 'Local HEAD changed during deterministic probe.'
    Assert-True ($one -match '^[a-f0-9]{40}$') 'Local HEAD format mismatch.'
}

Test-Case 'gitflow clean-tree verifier uses isolated repository' {
    $repo = Join-Path $tempRoot ('aria-gitflow-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $repo -Force | Out-Null

        $init = Invoke-AriaGitProcess -Arguments @('init') -RepositoryRoot $repo
        Assert-Equal 0 $init.exitCode 'Temporary Git initialization failed.'

        [IO.File]::WriteAllText(
            (Join-Path $repo 'probe.txt'),
            'ARIA Gitflow probe',
            [Text.UTF8Encoding]::new($false)
        )

        $add = Invoke-AriaGitProcess -Arguments @('add','probe.txt') -RepositoryRoot $repo
        Assert-Equal 0 $add.exitCode 'Temporary Git add failed.'

        $commit = Invoke-AriaGitProcess `
            -Arguments @(
                '-c','user.name=ARIA',
                '-c','user.email=aria@local.invalid',
                'commit','-m','initial'
            ) `
            -RepositoryRoot $repo
        Assert-Equal 0 $commit.exitCode 'Temporary Git commit failed.'

        $clean = Assert-AriaGitClean -RepositoryRoot $repo
        Assert-True $clean 'Clean-tree verification rejected an isolated clean repository.'
    }
    finally {
        Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'gitflow verification event is single-frame capable' {
    $command = Get-Command Write-AriaGitVerification -ErrorAction Stop
    Assert-Equal 'Function' ([string]$command.CommandType) 'Gitflow verification renderer is not exported.'
}
Test-Case 'gitflow process rejects function shadowing' {
    function git { param([string[]]$Arguments) throw 'shadow function should never execute' }
    try {
        $result = Invoke-AriaGitProcess -Arguments @('--version') -RepositoryRoot $root
        Assert-Equal 0 $result.exitCode 'Git application invocation failed.'
        Assert-True ($result.stdout -match '^git version') 'Git application output was not captured.'
    }
    finally {
        Remove-Item Function:\git -ErrorAction SilentlyContinue
    }
}
Test-Case 'oscillator frame preserves rectangular width' {
    $state = New-AriaBufferState -Label probe -Width 12
    $frame = Get-AriaBufferFrame -State $state
    Assert-True ($frame -match '⟦.{12}⟧$') 'Oscillator rectangle width changed.'
    Assert-Equal 1 ([regex]::Matches($frame,'◆').Count) 'Oscillator must contain one moving pulse.'
}

Test-Case 'oscillator reverses at both boundaries' {
    $state = New-AriaBufferState -Label probe -Width 8
    $state.position = 7
    $state.direction = 1
    $null = Step-AriaBuffer -State $state
    Assert-Equal '-1' ([string][int]$state.direction) 'Oscillator did not reverse at the right boundary.'

    $state.position = 0
    $state.direction = -1
    $null = Step-AriaBuffer -State $state
    Assert-Equal '1' ([string][int]$state.direction) 'Oscillator did not reverse at the left boundary.'
}

Test-Case 'oscillator suppresses animation in CI' {
    $prior = $env:CI
    try {
        $env:CI = 'true'
        Assert-True (-not (Test-AriaInteractiveBuffer)) 'CI animation suppression failed.'
    }
    finally {
        $env:CI = $prior
    }
}
Test-Case 'bufferflow cycles transmission phases' {
    $state = New-AriaTransmissionBuffer -Label probe -Width 12
    $phases = New-Object 'System.Collections.Generic.HashSet[string]'
    for ($index = 0; $index -lt 16; $index++) {
        [void]$phases.Add((Get-AriaTransmissionPhase -State $state))
        $null = Step-AriaTransmissionBuffer -State $state
    }

    Assert-True ($phases.Contains('mesh')) 'Bufferflow mesh phase missing.'
    Assert-True ($phases.Contains('transmit')) 'Bufferflow transmit phase missing.'
    Assert-True ($phases.Contains('align')) 'Bufferflow align phase missing.'
    Assert-True ($phases.Contains('verify')) 'Bufferflow verify phase missing.'
}

Test-Case 'bufferflow geometry converges during alignment' {
    $state = New-AriaTransmissionBuffer -Label probe -Width 12
    $state.tick = 9
    $state.position = 0
    $before = [math]::Abs($state.position - 5)
    $null = Step-AriaTransmissionBuffer -State $state
    $after = [math]::Abs($state.position - 5)
    Assert-True ($after -lt $before) 'Alignment phase did not converge toward center geometry.'
}

Test-Case 'bufferflow completion frame locks geometry' {
    $state = New-AriaTransmissionBuffer -Label probe -Width 12
    $state.interactive = $false
    $frame = Get-AriaTransmissionFrame -State $state
    Assert-True ($frame -match '⟦.{12}⟧') 'Transmission frame width changed.'
    Assert-True ($frame -match 'mesh') 'Transmission phase label missing.'
}

Test-Case 'bufferflow process returns one typed result' {
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $git) {
        $git = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    $path = $null
    foreach ($propertyName in @('Path','Source','Definition','Name')) {
        $property = $git.PSObject.Properties[$propertyName]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            $path = [string]$property.Value
            break
        }
    }

    $result = @(Invoke-AriaBufferedProcess `
        -FilePath $path `
        -ArgumentList @('--version') `
        -WorkingDirectory $root `
        -Label 'probe.git' `
        -Mode verification)

    Assert-Equal '1' ([string]$result.Count) 'Buffered process emitted more than one pipeline object.'
    Assert-Equal '0' ([string][int]$result[0].exitCode) 'Buffered process exit code mismatch.'
}
Test-Case 'signal receipt reports duration bytes and coherence' {
    $start = [datetime]'2026-01-01T00:00:00Z'
    $end = $start.AddMilliseconds(125)
    $receipt = New-AriaTransmissionReceipt `
        -Label probe `
        -Mode remote `
        -ExitCode 0 `
        -StartedAt $start `
        -CompletedAt $end `
        -Stdout 'abc' `
        -Stderr ''

    Assert-Equal 'aligned' ([string]$receipt.coherence) 'Receipt coherence mismatch.'
    Assert-Equal '125' ([string][int]$receipt.durationMs) 'Receipt duration mismatch.'
    Assert-Equal '3' ([string][int]$receipt.totalBytes) 'Receipt byte count mismatch.'
}

Test-Case 'signal receipt formats as a subordinate line' {
    $start = [datetime]'2026-01-01T00:00:00Z'
    $receipt = New-AriaTransmissionReceipt `
        -Label probe `
        -Mode verification `
        -ExitCode 0 `
        -StartedAt $start `
        -CompletedAt $start `
        -Stdout '' `
        -Stderr ''

    $line = Format-AriaTransmissionReceipt -Receipt $receipt
    Assert-True ($line -match '^└─ ∿ verifier · aligned') 'Receipt is not subordinate transmission feedback.'
}

Test-Case 'buffered sequence activates every item' {
    $prior = $env:CI
    try {
        $env:CI = 'true'
        $items = @(
            [pscustomobject]@{ name = 'one'; mode = 'local'; action = { 'a' } },
            [pscustomobject]@{ name = 'two'; mode = 'verification'; action = { 'b' } }
        )

        $results = @(Invoke-AriaBufferedSequence -Items $items)
        Assert-Equal '2' ([string]$results.Count) 'Buffered sequence skipped an item.'
        Assert-Equal 'one' ([string]$results[0].name) 'First buffered item identity mismatch.'
        Assert-Equal 'two' ([string]$results[1].name) 'Second buffered item identity mismatch.'
    }
    finally {
        $env:CI = $prior
    }
}

Test-Case 'buffered process carries transmission receipt' {
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $git) {
        $git = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    $path = $null
    foreach ($propertyName in @('Path','Source','Definition','Name')) {
        $property = $git.PSObject.Properties[$propertyName]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            $path = [string]$property.Value
            break
        }
    }

    $prior = $env:CI
    try {
        $env:CI = 'true'
        $result = Invoke-AriaBufferedProcess `
            -FilePath $path `
            -ArgumentList @('--version') `
            -WorkingDirectory $root `
            -Label 'probe.git' `
            -Mode verification

        Assert-True ($null -ne $result.receipt) 'Buffered process receipt missing.'
        Assert-Equal 'aligned' ([string]$result.receipt.coherence) 'Buffered process receipt coherence mismatch.'
    }
    finally {
        $env:CI = $prior
    }
}
Test-Case 'typed core canonicalizes generic and record types' {
    $int = New-AriaType -Kind Int
    $text = New-AriaType -Kind Text
    $result = New-AriaType -Kind Result -Arguments @($int,$text)
    $record = New-AriaType -Kind Record -Fields @{ z=$text; a=$result }

    Assert-Equal 'Result<Int,Text>' (ConvertTo-AriaCanonicalType $result) 'Result type canonicalization failed.'
    Assert-Equal 'Record{a:Result<Int,Text>,z:Text}' (ConvertTo-AriaCanonicalType $record) 'Record fields are not canonicalized.'
}

Test-Case 'typed core rejects immutable reassignment' {
    $scope = New-AriaScope
    $int = New-AriaType -Kind Int
    $null = Add-AriaBinding -Scope $scope -Name value -Type $int -Value 1
    $error = Set-AriaBindingValue -Scope $scope -Name value -Type $int -Value 2

    Assert-Equal 'E_BIND_IMMUTABLE' ([string]$error.code) 'Immutable binding was not rejected.'
}

Test-Case 'typed core rejects wrong function argument types' {
    $int = New-AriaType -Kind Int
    $text = New-AriaType -Kind Text
    $signature = New-AriaFunctionSignature `
        -Name addOne `
        -Parameters @([pscustomobject]@{name='value';type=$int}) `
        -ReturnType $int

    $result = Test-AriaFunctionCall -Signature $signature -ArgumentTypes @($text)
    Assert-True (-not [bool]$result.valid) 'Wrong function argument type was accepted.'
    Assert-Equal 'E_CALL_TYPE' ([string]$result.errors[0].code) 'Wrong function error code.'
}

Test-Case 'typed core rejects missing function capabilities' {
    $unit = New-AriaType -Kind Unit
    $signature = New-AriaFunctionSignature `
        -Name send `
        -ReturnType $unit `
        -Effects @('network.send') `
        -Capabilities @('cap:network')

    $result = Test-AriaFunctionCall -Signature $signature -GrantedCapabilities @()
    Assert-True (-not [bool]$result.valid) 'Missing capability was accepted.'
    Assert-Equal 'E_CAPABILITY_MISSING' ([string]$result.errors[0].code) 'Capability error code mismatch.'
}

Test-Case 'typed core detects non-exhaustive branches' {
    $result = Test-AriaExhaustiveBranch `
        -Variants @('ok','error') `
        -Cases @('ok')

    Assert-True (-not [bool]$result.exhaustive) 'Non-exhaustive branch was accepted.'
    Assert-Equal 'error' ([string]$result.missing[0]) 'Missing variant was not reported.'
}

Test-Case 'typed core validates effect authority' {
    $denied = Test-AriaEffectAuthority -Effects @('memory.write') -Capabilities @()
    $allowed = Test-AriaEffectAuthority -Effects @('memory.write') -Capabilities @('cap:memory.write')

    Assert-True (-not [bool]$denied.valid) 'Unauthorized effect was accepted.'
    Assert-True ([bool]$allowed.valid) 'Authorized effect was rejected.'
}

Test-Case 'typed IR accepts valid golden fixture' {
    $path = Join-Path $root 'tests/fixtures/typed-core/valid-function.ariair.json'
    $result = Test-AriaTypedIrFile -Path $path

    Assert-True ([bool]$result.valid) 'Valid typed IR fixture was rejected.'
    Assert-Equal '64' ([string]$result.digest.Length) 'Typed IR digest length mismatch.'
}

Test-Case 'typed IR rejects missing capability fixture' {
    $path = Join-Path $root 'tests/fixtures/typed-core/invalid-capability.ariair.json'
    $result = Test-AriaTypedIrFile -Path $path

    Assert-True (-not [bool]$result.valid) 'Capability-invalid typed IR was accepted.'
    Assert-Equal 'E_EFFECT_AUTHORITY' ([string]$result.errors[0].code) 'Typed IR authority rejection mismatch.'
}

Test-Case 'typed IR digest is deterministic' {
    $path = Join-Path $root 'tests/fixtures/typed-core/valid-function.ariair.json'
    $first = Test-AriaTypedIrFile -Path $path
    $second = Test-AriaTypedIrFile -Path $path

    Assert-Equal ([string]$first.digest) ([string]$second.digest) 'Typed IR digest changed across verification.'
    Assert-Equal ([string]$first.canonical) ([string]$second.canonical) 'Typed IR canonical form changed.'
}

Test-Case 'typed IR rejects unknown opcode' {
    $document = [pscustomobject]@{
        schema = 'aria.typed-ir/0.2'
        entry = 'main'
        functions = @(
            [pscustomobject]@{
                name = 'main'
                parameters = @()
                returnType = 'Unit'
                effects = @()
                capabilities = @()
                instructions = @([pscustomobject]@{op='teleport'})
            }
        )
    }

    $result = Test-AriaTypedIr -Document $document
    Assert-True (-not [bool]$result.valid) 'Unknown opcode was accepted.'
    Assert-Equal 'E_IR_OPCODE' ([string]$result.errors[0].code) 'Unknown opcode error code mismatch.'
}
function New-TestGraphRule {
    [pscustomobject]@{
        schema = 'aria.graph-rule/0.3'
        name = 'grant_access'
        pattern = [pscustomobject]@{
            sourceType = 'User'
            edgeType = 'requests'
            targetType = 'Resource'
            sourceWhere = @{ status = 'active' }
            targetWhere = @{}
        }
        guard = [pscustomobject]@{
            kind = 'eq'
            left = 'source.status'
            right = 'active'
        }
        capabilities = @('cap:graph.write')
        rewrite = @(
            [pscustomobject]@{
                op = 'remove.edge'
                id = '$edge.id'
            },
            [pscustomobject]@{
                op = 'add.edge'
                id = 'edge:access:1'
                type = 'access'
                source = '$source.id'
                target = '$target.id'
            }
        )
    }
}

Test-Case 'graph core accepts valid typed graph' {
    $graph = Get-Content (Join-Path $root 'tests/fixtures/graph-core/valid-access-graph.json') -Raw | ConvertFrom-Json
    $result = Test-AriaGraph $graph
    Assert-True ([bool]$result.valid) 'Valid typed graph was rejected.'
}

Test-Case 'graph core rejects dangling edge' {
    $graph = Get-Content (Join-Path $root 'tests/fixtures/graph-core/invalid-dangling-edge.json') -Raw | ConvertFrom-Json
    $result = Test-AriaGraph $graph
    Assert-True (-not [bool]$result.valid) 'Dangling edge was accepted.'
    Assert-Equal 'E_GRAPH_EDGE_DANGLING' ([string]$result.errors[0].code) 'Dangling edge error mismatch.'
}

Test-Case 'graph core rejects duplicate node identity' {
    $graph = Get-Content (Join-Path $root 'tests/fixtures/graph-core/valid-access-graph.json') -Raw | ConvertFrom-Json
    $graph.nodes = @($graph.nodes) + @([pscustomobject]@{id='user:42';type='User'})
    $result = Test-AriaGraph $graph
    Assert-True (-not [bool]$result.valid) 'Duplicate node identity was accepted.'
}

Test-Case 'graph core rejects endpoint type mismatch' {
    $graph = Get-Content (Join-Path $root 'tests/fixtures/graph-core/valid-access-graph.json') -Raw | ConvertFrom-Json
    $graph.nodes[0].type = 'Resource'
    $result = Test-AriaGraph $graph
    Assert-True (-not [bool]$result.valid) 'Invalid edge endpoint typing was accepted.'
}

Test-Case 'graph pattern returns typed bindings' {
    $graph = Get-Content (Join-Path $root 'tests/fixtures/graph-core/valid-access-graph.json') -Raw | ConvertFrom-Json
    $rule = New-TestGraphRule
    $matches = @(Find-AriaGraphMatches -Graph $graph -Pattern $rule.pattern)
    Assert-Equal '1' ([string]$matches.Count) 'Typed pattern match count mismatch.'
    Assert-Equal 'User' ([string]$matches[0].source.type) 'Source binding type mismatch.'
    Assert-Equal 'Resource' ([string]$matches[0].target.type) 'Target binding type mismatch.'
}

Test-Case 'graph guard rejects unsupported kind' {
    $graph = Get-Content (Join-Path $root 'tests/fixtures/graph-core/valid-access-graph.json') -Raw | ConvertFrom-Json
    $rule = New-TestGraphRule
    $match = @(Find-AriaGraphMatches -Graph $graph -Pattern $rule.pattern)[0]
    $guard = Test-AriaGraphGuard -Guard ([pscustomobject]@{kind='execute'}) -Match $match
    Assert-True (-not [bool]$guard.valid) 'Unsupported graph guard was accepted.'
    Assert-Equal 'E_GRAPH_GUARD_KIND' ([string]$guard.error.code) 'Graph guard error mismatch.'
}

Test-Case 'graph rule rejects missing capability' {
    $rule = New-TestGraphRule
    $result = Test-AriaGraphRule -Rule $rule -GrantedCapabilities @()
    Assert-True (-not [bool]$result.valid) 'Missing graph capability was accepted.'
    Assert-Equal 'E_GRAPH_CAPABILITY' ([string]$result.errors[0].code) 'Graph capability error mismatch.'
}

Test-Case 'graph rewrite commits valid transaction' {
    $graph = Get-Content (Join-Path $root 'tests/fixtures/graph-core/valid-access-graph.json') -Raw | ConvertFrom-Json
    $result = Invoke-AriaGraphRewrite -Graph $graph -Rule (New-TestGraphRule) -GrantedCapabilities @('cap:graph.write')
    Assert-True ([bool]$result.committed) 'Valid graph rewrite did not commit.'
    Assert-True ([string]$result.beforeDigest -cne [string]$result.afterDigest) 'Committed rewrite did not change graph identity.'
}

Test-Case 'graph rewrite removes matched edge' {
    $graph = Get-Content (Join-Path $root 'tests/fixtures/graph-core/valid-access-graph.json') -Raw | ConvertFrom-Json
    $result = Invoke-AriaGraphRewrite -Graph $graph -Rule (New-TestGraphRule) -GrantedCapabilities @('cap:graph.write')
    $requests = @($result.graph.edges | Where-Object {$_.type -eq 'requests'})
    $access = @($result.graph.edges | Where-Object {$_.type -eq 'access'})
    Assert-Equal '0' ([string]$requests.Count) 'Matched request edge remained after rewrite.'
    Assert-Equal '1' ([string]$access.Count) 'Access edge was not created.'
}

Test-Case 'graph rewrite rejects false guard without mutation' {
    $graph = Get-Content (Join-Path $root 'tests/fixtures/graph-core/valid-access-graph.json') -Raw | ConvertFrom-Json
    $rule = New-TestGraphRule
    $rule.guard.right = 'disabled'
    $before = Get-AriaGraphDigest $graph
    $result = Invoke-AriaGraphRewrite -Graph $graph -Rule $rule -GrantedCapabilities @('cap:graph.write')
    Assert-True ([bool]$result.rejected) 'False guard did not reject rewrite.'
    Assert-Equal 'guard-false' ([string]$result.reason) 'False guard rejection reason mismatch.'
    Assert-Equal $before ([string]$result.afterDigest) 'False guard changed graph identity.'
}

Test-Case 'graph rewrite rolls back invalid candidate' {
    $graph = Get-Content (Join-Path $root 'tests/fixtures/graph-core/valid-access-graph.json') -Raw | ConvertFrom-Json
    $rule = New-TestGraphRule
    $rule.rewrite[1].target = 'resource:missing'
    $before = Get-AriaGraphDigest $graph
    $result = Invoke-AriaGraphRewrite -Graph $graph -Rule $rule -GrantedCapabilities @('cap:graph.write')
    Assert-True ([bool]$result.rejected) 'Invalid candidate graph was committed.'
    Assert-Equal 'result-invalid' ([string]$result.reason) 'Rollback rejection reason mismatch.'
    Assert-Equal $before ([string]$result.afterDigest) 'Rollback did not preserve original graph identity.'
}

Test-Case 'graph rewrite event is content addressed' {
    $graph = Get-Content (Join-Path $root 'tests/fixtures/graph-core/valid-access-graph.json') -Raw | ConvertFrom-Json
    $result = Invoke-AriaGraphRewrite -Graph $graph -Rule (New-TestGraphRule) -GrantedCapabilities @('cap:graph.write')
    Assert-True ([string]$result.event.transaction -match '^sha256:[a-f0-9]{64}$') 'Graph transaction event is not content addressed.'
    Assert-Equal 'aria.graph.rewrite.committed' ([string]$result.event.type) 'Graph event type mismatch.'
}
function Get-TestReplayInputs {
    [pscustomobject]@{
        graph = Get-Content (Join-Path $root 'tests/fixtures/graph-replay/initial-access-graph.json') -Raw | ConvertFrom-Json
        rule = Get-Content (Join-Path $root 'tests/fixtures/graph-replay/grant-access-rule.json') -Raw | ConvertFrom-Json
    }
}

Test-Case 'semantic diff reports removed and added edges' {
    $input = Get-TestReplayInputs
    $rewrite = Invoke-AriaGraphRewrite -Graph $input.graph -Rule $input.rule -GrantedCapabilities @('cap:graph.write')
    $diff = Compare-AriaGraphSemantic -Before $input.graph -After $rewrite.graph

    Assert-True ([bool]$diff.valid) 'Semantic graph diff was invalid.'
    Assert-Equal '1' ([string]@($diff.edges.removed).Count) 'Removed edge was not reported.'
    Assert-Equal '1' ([string]@($diff.edges.added).Count) 'Added edge was not reported.'
}

Test-Case 'semantic diff is stable for identical graphs' {
    $input = Get-TestReplayInputs
    $diff = Compare-AriaGraphSemantic -Before $input.graph -After (Copy-AriaGraph $input.graph)

    Assert-True (-not [bool]$diff.changed) 'Identical graphs produced a semantic change.'
    Assert-Equal ([string]$diff.beforeDigest) ([string]$diff.afterDigest) 'Identical graph digests diverged.'
}

Test-Case 'graph transition is content addressed' {
    $input = Get-TestReplayInputs
    $before = Get-AriaGraphDigest $input.graph
    $result = New-AriaGraphTransition `
        -Sequence 1 `
        -Parent ("sha256:$before") `
        -BeforeGraph $input.graph `
        -Rule $input.rule `
        -GrantedCapabilities @('cap:graph.write')

    Assert-True ([bool]$result.committed) 'Graph transition did not commit.'
    Assert-True ([string]$result.transition.id -match '^sha256:[a-f0-9]{64}$') 'Transition identity is not content addressed.'
}

Test-Case 'graph transition records capability authority' {
    $input = Get-TestReplayInputs
    $before = Get-AriaGraphDigest $input.graph
    $result = New-AriaGraphTransition `
        -Sequence 1 `
        -Parent ("sha256:$before") `
        -BeforeGraph $input.graph `
        -Rule $input.rule `
        -GrantedCapabilities @('cap:graph.write')

    Assert-Equal 'cap:graph.write' ([string]$result.transition.grantedCapabilities[0]) 'Granted graph authority was not recorded.'
}

Test-Case 'graph transition rejects tampered identity' {
    $input = Get-TestReplayInputs
    $before = Get-AriaGraphDigest $input.graph
    $result = New-AriaGraphTransition `
        -Sequence 1 `
        -Parent ("sha256:$before") `
        -BeforeGraph $input.graph `
        -Rule $input.rule `
        -GrantedCapabilities @('cap:graph.write')

    $result.transition.id = 'sha256:' + ('0' * 64)
    $validation = Test-AriaGraphTransition $result.transition
    Assert-True (-not [bool]$validation.valid) 'Tampered transition identity was accepted.'
    Assert-Equal 'E_REPLAY_IDENTITY' ([string]$validation.errors[0].code) 'Transition identity rejection mismatch.'
}

Test-Case 'transition chain accepts coherent history' {
    $input = Get-TestReplayInputs
    $before = Get-AriaGraphDigest $input.graph
    $result = New-AriaGraphTransition `
        -Sequence 1 `
        -Parent ("sha256:$before") `
        -BeforeGraph $input.graph `
        -Rule $input.rule `
        -GrantedCapabilities @('cap:graph.write')

    $chain = Test-AriaGraphTransitionChain -InitialGraphDigest $before -Transitions @($result.transition)
    Assert-True ([bool]$chain.valid) 'Coherent transition chain was rejected.'
    Assert-Equal ([string]$result.transition.afterDigest) ([string]$chain.finalDigest) 'Transition chain final digest mismatch.'
}

Test-Case 'transition chain rejects parent fracture' {
    $input = Get-TestReplayInputs
    $before = Get-AriaGraphDigest $input.graph
    $result = New-AriaGraphTransition `
        -Sequence 1 `
        -Parent ("sha256:$before") `
        -BeforeGraph $input.graph `
        -Rule $input.rule `
        -GrantedCapabilities @('cap:graph.write')

    $result.transition.parent = 'sha256:' + ('1' * 64)
    $chain = Test-AriaGraphTransitionChain -InitialGraphDigest $before -Transitions @($result.transition)
    Assert-True (-not [bool]$chain.valid) 'Broken transition parent was accepted.'
}

Test-Case 'transition chain rejects sequence fracture' {
    $input = Get-TestReplayInputs
    $before = Get-AriaGraphDigest $input.graph
    $result = New-AriaGraphTransition `
        -Sequence 1 `
        -Parent ("sha256:$before") `
        -BeforeGraph $input.graph `
        -Rule $input.rule `
        -GrantedCapabilities @('cap:graph.write')

    $result.transition.sequence = 2
    $chain = Test-AriaGraphTransitionChain -InitialGraphDigest $before -Transitions @($result.transition)
    Assert-True (-not [bool]$chain.valid) 'Broken transition sequence was accepted.'
}

Test-Case 'graph replay reproduces recorded digest' {
    $input = Get-TestReplayInputs
    $before = Get-AriaGraphDigest $input.graph
    $result = New-AriaGraphTransition `
        -Sequence 1 `
        -Parent ("sha256:$before") `
        -BeforeGraph $input.graph `
        -Rule $input.rule `
        -GrantedCapabilities @('cap:graph.write')

    $replay = Invoke-AriaGraphReplay -InitialGraph $input.graph -Transitions @($result.transition)
    Assert-True ([bool]$replay.valid) 'Deterministic graph replay failed.'
    Assert-Equal ([string]$result.transition.afterDigest) ([string]$replay.digest) 'Replay digest did not reproduce recorded state.'
}

Test-Case 'graph replay rejects digest divergence' {
    $input = Get-TestReplayInputs
    $before = Get-AriaGraphDigest $input.graph
    $result = New-AriaGraphTransition `
        -Sequence 1 `
        -Parent ("sha256:$before") `
        -BeforeGraph $input.graph `
        -Rule $input.rule `
        -GrantedCapabilities @('cap:graph.write')

    $result.transition.afterDigest = ('f' * 64)
    $replay = Invoke-AriaGraphReplay -InitialGraph $input.graph -Transitions @($result.transition)
    Assert-True (-not [bool]$replay.valid) 'Replay digest divergence was accepted.'
}

Test-Case 'historical graph state reconstructs sequence zero' {
    $input = Get-TestReplayInputs
    $before = Get-AriaGraphDigest $input.graph
    $result = New-AriaGraphTransition `
        -Sequence 1 `
        -Parent ("sha256:$before") `
        -BeforeGraph $input.graph `
        -Rule $input.rule `
        -GrantedCapabilities @('cap:graph.write')

    $state = Get-AriaGraphStateAt -InitialGraph $input.graph -Transitions @($result.transition) -Sequence 0
    Assert-True ([bool]$state.valid) 'Sequence-zero graph reconstruction failed.'
    Assert-Equal $before ([string]$state.digest) 'Sequence-zero graph identity mismatch.'
}

Test-Case 'historical graph state reconstructs committed transition' {
    $input = Get-TestReplayInputs
    $before = Get-AriaGraphDigest $input.graph
    $result = New-AriaGraphTransition `
        -Sequence 1 `
        -Parent ("sha256:$before") `
        -BeforeGraph $input.graph `
        -Rule $input.rule `
        -GrantedCapabilities @('cap:graph.write')

    $state = Get-AriaGraphStateAt -InitialGraph $input.graph -Transitions @($result.transition) -Sequence 1
    Assert-True ([bool]$state.valid) 'Committed graph state reconstruction failed.'
    Assert-Equal ([string]$result.transition.afterDigest) ([string]$state.digest) 'Historical graph state digest mismatch.'
}
$script:SuiteClock.Stop()
$null = Complete-AriaEnumerator -Detail ("{0} passed · {1} failed" -f $script:Passed,$script:Failed)
if ($script:Failed -gt 0) { throw "ARIA test suite failed: $script:Failed failure(s)." }
