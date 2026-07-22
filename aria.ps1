[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Command = 'help',
    [Parameter(Position=1)][string]$Path,
    [string]$Out,
    [string]$Policy,
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
Import-Module (Join-Path $root 'src/Aria.Common.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Lexer.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Parser.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Semantics.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Bytecode.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.Gate.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'src/Aria.VM.psm1') -Force -DisableNameChecking

function Show-AriaHelp {
    Write-AriaBanner -Title 'ARIA / LANGUAGE LABORATORY'
    @'
  aria doctor [-Workspace <repository>] [-Strict]
  aria verify
  aria manifest
  aria test
  aria gate|check <program.aria> [-Workspace <repository>] [-Strict]
  aria compile|build <program.aria> [-Out <program.ariac>] [-Workspace <repository>] [-Strict]
  aria run|start|trace <program.aria> [-Out <program.ariac>] [-Workspace <repository>] [-Strict]
  aria connect [program.aria] [-Workspace <repository>] [-Strict]
  aria exec <program.ariac> [-Workspace <repository>] [-Strict]
  aria inspect <program.ariac>
  aria graph <program.aria|program.ariac>
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
        'doctor' {
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
            $probe = Join-Path $env:TEMP ('aria-gzip-' + [guid]::NewGuid().ToString('N') + '.bin')
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
            Write-AriaTreeStage -Name 'semantic pipeline' -State Pulse -Detail $Path
            $result = Invoke-AriaGate -SourcePath $Path -PolicyPath $Policy -WorkspaceRoot $workspaceRoot -StrictRepository:$Strict
            $clock.Stop()
            Write-AriaSummary -Title 'SOURCE ACCEPTED' -Passed $true -Detail $result.bytecode.programName -Duration $clock.Elapsed
            if ($script:VerboseOutput) { Write-AriaKeyValue -Key 'build hash' -Value $result.buildHash }
        }
        { $_ -in @('compile','build') } {
            if (-not $Path) { throw 'compile requires a .aria source path.' }
            $clock = [Diagnostics.Stopwatch]::StartNew()
            Write-AriaBanner -Title 'ARIA / COMPILE'
            Write-AriaTreeStage -Name 'compiler pipeline' -State Pulse -Detail $Path
            $result = Invoke-AriaCompile -SourcePath $Path -PolicyPath $Policy -OutputPath $Out -WorkspaceRoot $workspaceRoot -StrictRepository:$Strict
            $clock.Stop()
            Write-AriaTreeStage -Name 'artifact' -State Pass -Detail $result.artifactPath
            Write-AriaSummary -Title 'BUILD COMPLETE' -Passed $true -Detail $result.gate.bytecode.programName -Duration $clock.Elapsed
        }
        { $_ -in @('run','start','trace') } {
            if (-not $Path) { $Path = Join-Path $root 'examples/hello.aria' }
            $clock = [Diagnostics.Stopwatch]::StartNew()
            Write-AriaBanner -Title 'ARIA / RUN'
            Write-AriaTreeStage -Name 'compiler pipeline' -State Pulse -Detail $Path
            $compiled = Invoke-AriaCompile -SourcePath $Path -PolicyPath $Policy -OutputPath $Out -WorkspaceRoot $workspaceRoot -StrictRepository:$Strict
            Write-AriaTreeStage -Name 'artifact' -State Pass -Detail $compiled.artifactPath
            Write-AriaTreeStage -Name 'virtual machine' -State Pulse -Detail 'local execution'
            $null = Invoke-AriaArtifact -Path $compiled.artifactPath -PolicyPath $Policy -WorkspaceRoot $workspaceRoot
            $clock.Stop()
            Write-AriaSummary -Title 'EXECUTION COMPLETE' -Passed $true -Detail $compiled.gate.bytecode.programName -Duration $clock.Elapsed
        }
        'connect' {
            if (-not $Path) { $Path = Join-Path $root 'examples/connection.aria' }
            $clock = [Diagnostics.Stopwatch]::StartNew()
            Write-AriaBanner -Title 'ARIA / CONNECTION' -Subtitle 'human intent · agent proposal · explicit consent · deterministic closure'
            Write-AriaTreeStage -Name 'connection compiler' -State Pulse -Detail $Path
            $compiled = Invoke-AriaCompile -SourcePath $Path -PolicyPath $Policy -OutputPath $Out -WorkspaceRoot $workspaceRoot -StrictRepository:$Strict
            Write-AriaTreeStage -Name 'connection artifact' -State Pass -Detail $compiled.artifactPath
            Write-AriaTreeStage -Name 'connection protocol' -State Pulse -Detail 'local verified session'
            $null = Invoke-AriaArtifact -Path $compiled.artifactPath -PolicyPath $Policy -WorkspaceRoot $workspaceRoot
            $clock.Stop()
            Write-AriaSummary -Title 'CONNECTION COMPLETE' -Passed $true -Detail $compiled.gate.bytecode.programName -Duration $clock.Elapsed
        }
        'exec' {
            if (-not $Path) { throw 'exec requires an .ariac artifact path.' }
            $clock = [Diagnostics.Stopwatch]::StartNew()
            Write-AriaBanner -Title 'ARIA / EXECUTE'
            if ($Strict) { $null = Assert-AriaRepositoryManifest }
            Write-AriaTreeStage -Name 'artifact verification' -State Pulse -Detail $Path
            $null = Invoke-AriaArtifact -Path $Path -PolicyPath $Policy -WorkspaceRoot $workspaceRoot
            $clock.Stop()
            Write-AriaSummary -Title 'EXECUTION COMPLETE' -Passed $true -Duration $clock.Elapsed
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
