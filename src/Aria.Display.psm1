Import-Module (Join-Path $PSScriptRoot 'Aria.Etherflow.psm1') -Force -DisableNameChecking
Set-StrictMode -Version 2.0

$script:Esc = [char]27
$script:SupportsAnsi = $false
if (-not $env:NO_COLOR -and $env:ARIA_COLOR -ne '0') {
    try {
        if ($Host.UI.PSObject.Properties.Name -contains 'SupportsVirtualTerminal') {
            $script:SupportsAnsi = [bool]$Host.UI.SupportsVirtualTerminal
        }
    }
    catch { $script:SupportsAnsi = $false }
    if (-not $script:SupportsAnsi -and ($env:WT_SESSION -or $env:ANSICON -or $env:ConEmuANSI -eq 'ON' -or $env:TERM -match 'xterm|ansi|color')) {
        $script:SupportsAnsi = $true
    }
}

function Get-AriaConsoleColor {
    param([string]$Name)
    switch ($Name) {
        'Cyan' { return 'Cyan' }
        'Magenta' { return 'Magenta' }
        'Green' { return 'Green' }
        'Yellow' { return 'Yellow' }
        'Red' { return 'Red' }
        'Gray' { return 'DarkGray' }
        default { return 'White' }
    }
}

function Get-AriaAnsiColor {
    param([string]$Name)
    switch ($Name) {
        'Cyan' { return '96' }
        'Magenta' { return '95' }
        'Green' { return '92' }
        'Yellow' { return '93' }
        'Red' { return '91' }
        'Gray' { return '90' }
        default { return '97' }
    }
}

function Write-AriaPaint {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text,
        [string]$Color = 'White',
        [switch]$Bold,
        [switch]$Pulse,
        [switch]$NoNewline
    )
    if ($script:SupportsAnsi) {
        $codes = New-Object System.Collections.Generic.List[string]
        $codes.Add((Get-AriaAnsiColor -Name $Color))
        if ($Bold) { $codes.Add('1') }
        if ($Pulse) { $codes.Add('5') }
        $painted = "$script:Esc[$($codes -join ';')m$Text$script:Esc[0m"
        Write-Host $painted -NoNewline:$NoNewline
    }
    else {
        Write-Host $Text -ForegroundColor (Get-AriaConsoleColor -Name $Color) -NoNewline:$NoNewline
    }
}

function Format-AriaDuration {
    param($Duration)
    if ($null -eq $Duration) { return '' }
    if ($Duration.TotalSeconds -ge 1) { return ('{0:0.00}s' -f $Duration.TotalSeconds) }
    return ('{0}ms' -f [math]::Max(1, [int][math]::Round($Duration.TotalMilliseconds)))
}

function Write-AriaBanner {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [string]$Subtitle = 'gated compiler · compressed bytecode · local virtual machine'
    )
    Write-Host ''
    Write-AriaPaint -Text '◆' -Color Magenta -Bold -NoNewline
    Write-AriaPaint -Text ('  {0}' -f $Title.ToUpperInvariant()) -Color Cyan -Bold -NoNewline
    if ($Subtitle) {
        Write-AriaPaint -Text ('   {0}' -f $Subtitle) -Color Gray
    }
    else {
        Write-Host ''
    }
}

function Write-AriaStage {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][ValidateSet('Pulse','Pass','Reject','Fail','Warn','Info')][string]$State,
        [string]$Detail = '',
        $Duration,
        [string]$Prefix = ''
    )
    $glyph = '◇'
    $color = 'Cyan'
    $label = 'READY'
    $pulse = $false
    switch ($State) {
        'Pulse' { $glyph = '◈'; $color = 'Magenta'; $label = 'ACTIVE'; $pulse = $true }
        'Pass'  { $glyph = '◆'; $color = 'Green'; $label = 'PASS' }
        'Reject'{ $glyph = '◆'; $color = 'Green'; $label = 'REJECT' }
        'Fail'  { $glyph = '⬗'; $color = 'Red'; $label = 'FAIL' }
        'Warn'  { $glyph = '⬖'; $color = 'Yellow'; $label = 'WARN' }
        'Info'  { $glyph = '◇'; $color = 'Cyan'; $label = 'INFO' }
    }
    if ($State -eq 'Pulse' -and $env:ARIA_ANIMATION -ne '0' -and $env:CI -ne 'true' -and [Environment]::UserInteractive) {
        foreach ($frame in @('◇','◈','◆','◈')) {
            Write-Host "`r" -NoNewline
            if ($Prefix) { Write-AriaPaint -Text $Prefix -Color Gray -NoNewline }
            Write-AriaPaint -Text $frame -Color Magenta -Bold -NoNewline
            Start-Sleep -Milliseconds 55
        }
        Write-Host "`r" -NoNewline
    }
    $durationText = Format-AriaDuration -Duration $Duration
    $suffixParts = New-Object System.Collections.Generic.List[string]
    if ($durationText) { $suffixParts.Add($durationText) }
    if ($Detail) { $suffixParts.Add($Detail) }
    $suffix = if ($suffixParts.Count -gt 0) { '  ' + ($suffixParts -join ' · ') } else { '' }
    if ($Prefix) { Write-AriaPaint -Text $Prefix -Color Gray -NoNewline }
    Write-AriaPaint -Text $glyph -Color $color -Bold -Pulse:$pulse -NoNewline
    Write-AriaPaint -Text ('  {0,-28}' -f $Name) -Color White -NoNewline
    Write-AriaPaint -Text ('{0,-7}' -f $label) -Color $color -Bold -NoNewline
    Write-AriaPaint -Text $suffix -Color Gray
}


function Get-AriaTreePrefix {
    param([int]$Depth = 0, [switch]$Last)
    $parts = New-Object System.Collections.Generic.List[string]
    for ($index = 0; $index -lt $Depth; $index++) { $parts.Add('│  ') }
    $parts.Add($(if ($Last) { '└─ ' } else { '├─ ' }))
    return ($parts -join '')
}

function Write-AriaTreeStage {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][ValidateSet('Pulse','Pass','Reject','Fail','Warn','Info')][string]$State,
        [string]$Detail = '',
        $Duration,
        [int]$Depth = 0,
        [switch]$Last
    )
    Write-AriaStage -Name $Name -State $State -Detail $Detail -Duration $Duration -Prefix (Get-AriaTreePrefix -Depth $Depth -Last:$Last)
}

function Write-AriaTreeText {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text,
        [string]$Glyph = '◇',
        [string]$Color = 'Cyan',
        [int]$Depth = 0,
        [switch]$Last
    )
    Write-AriaPaint -Text (Get-AriaTreePrefix -Depth $Depth -Last:$Last) -Color Gray -NoNewline
    Write-AriaPaint -Text $Glyph -Color $Color -Bold -NoNewline
    Write-AriaPaint -Text ('  ' + $Text) -Color White
}

function Write-AriaTrunk {
    param([int]$Depth = 0)
    $prefix = ''
    for ($index = 0; $index -lt $Depth; $index++) { $prefix += '│  ' }
    Write-AriaPaint -Text ($prefix + '│') -Color Gray
}

function Write-AriaKeyValue {
    param([string]$Key, [AllowEmptyString()][string]$Value)
    Write-AriaPaint -Text '◇' -Color Cyan -NoNewline
    Write-AriaPaint -Text ('  {0,-14}' -f $Key) -Color Gray -NoNewline
    Write-AriaPaint -Text $Value -Color White
}

function Write-AriaSummary {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][bool]$Passed,
        [string]$Detail = '',
        $Duration
    )
    Write-Host ''
    Write-AriaStage -Name $Title -State $(if ($Passed) { 'Pass' } else { 'Fail' }) -Detail $Detail -Duration $Duration
}

function Write-AriaStream {
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text)
    Write-AriaPaint -Text '∿' -Color Magenta -NoNewline
    Write-AriaPaint -Text ('  ' + $Text) -Color White
}


$script:AriaEnumeration = $null

function Start-AriaEnumerator {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [int]$Expected = 0,
        [string]$Domain = 'runtime'
    )

    $script:AriaEnumeration = [pscustomobject][ordered]@{
        Name = $Name
        Domain = $Domain
        Expected = $Expected
        Passed = 0
        Failed = 0
        Started = [Diagnostics.Stopwatch]::StartNew()
        Items = New-Object System.Collections.Generic.List[object]
    }

    Write-AriaPaint -Text '◈' -Color Magenta -Bold -NoNewline
    Write-AriaPaint -Text ("  {0}" -f $Name) -Color White -NoNewline
    if($Expected -gt 0){ Write-AriaPaint -Text ("  ×{0}" -f $Expected) -Color Gray }
    else { Write-Host '' }
}

function Add-AriaEnumerationItem {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][ValidateSet('Pass','Fail','Warn','Info')][string]$State,
        [string]$Detail = '',
        $Duration
    )

    if($null -eq $script:AriaEnumeration){ throw 'ARIA enumerator is not active.' }

    $item=[pscustomobject][ordered]@{
        Name=$Name
        State=$State
        Detail=$Detail
        Duration=$Duration
    }
    $script:AriaEnumeration.Items.Add($item)

    if($State -eq 'Pass'){
        $script:AriaEnumeration.Passed++
        if($env:ARIA_VERBOSE -eq '1'){
            Write-AriaStage -Name $Name -State Pass -Detail $Detail -Duration $Duration -Prefix '│  '
        }
        return
    }

    if($State -eq 'Fail'){ $script:AriaEnumeration.Failed++ }
    Write-AriaStage -Name $Name -State $State -Detail $Detail -Duration $Duration -Prefix '│  '
}

function Complete-AriaEnumerator {
    param([string]$Detail='')

    if($null -eq $script:AriaEnumeration){ throw 'ARIA enumerator is not active.' }

    $script:AriaEnumeration.Started.Stop()
    $total=$script:AriaEnumeration.Items.Count
    $passed=$script:AriaEnumeration.Passed
    $failed=$script:AriaEnumeration.Failed
    $state=if($failed -eq 0){'Pass'}else{'Fail'}
    $duration=Format-AriaDuration -Duration $script:AriaEnumeration.Started.Elapsed
    $coherence=if($failed -eq 0){'coherent'}else{"$failed fracture(s)"}
    $summary="{0}/{1} · {2} · {3}" -f $passed,$total,$duration,$coherence
    if($Detail){$summary+=" · $Detail"}

    Write-AriaStage -Name $script:AriaEnumeration.Name -State $state -Detail $summary
    $result=$script:AriaEnumeration
    $script:AriaEnumeration=$null
    $result
}

function Write-AriaCausalFrame {
    param(
        [Parameter(Mandatory=$true)][string]$Domain,
        [Parameter(Mandatory=$true)][string]$Phase,
        [Parameter(Mandatory=$true)][string]$State,
        [Parameter(Mandatory=$true)][string]$Information,
        [string]$Cause='',
        [string]$Effect='',
        $Duration
    )

    $glyph=if($State -eq 'PASS'){'◆'}elseif($State -eq 'FAIL'){'⬗'}else{'◈'}
    $color=if($State -eq 'PASS'){'Green'}elseif($State -eq 'FAIL'){'Red'}else{'Magenta'}
    $time=Format-AriaDuration -Duration $Duration
    $causal=''
    if($Cause -or $Effect){$causal=("  {0}→{1}" -f $Cause,$Effect)}
    if($time){$causal+="  @$time"}

    Write-AriaPaint -Text $glyph -Color $color -Bold -NoNewline
    Write-AriaPaint -Text ("  {0}.{1}" -f $Domain,$Phase) -Color Cyan -NoNewline
    Write-AriaPaint -Text ("  ∿ {0}" -f $Information) -Color White -NoNewline
    Write-AriaPaint -Text $causal -Color Gray
}
Export-ModuleMember -Function Write-AriaPaint, Write-AriaBanner, Write-AriaStage, Write-AriaTreeStage, Write-AriaTreeText, Write-AriaTrunk, Write-AriaKeyValue, Write-AriaSummary, Write-AriaStream, Format-AriaDuration, Start-AriaEnumerator, Add-AriaEnumerationItem, Complete-AriaEnumerator, Write-AriaCausalFrame

function Invoke-AriaEtherPreview {
    param([Parameter(Mandatory=$true)]$Transmission)

    $events = Get-AriaTriadicEventsFromTransmission -Transmission $Transmission
    foreach ($event in $events) {
        Write-AriaTriadicTransmission -Event $event
    }
}

function Test-AriaInteractiveBuffer {
    [CmdletBinding()]
    param()

    if ($env:CI -or $env:GITHUB_ACTIONS -eq 'true' -or $env:ARIA_NO_ANIMATION -eq '1') {
        return $false
    }

    try {
        return -not [Console]::IsOutputRedirected
    }
    catch {
        return $Host.Name -eq 'ConsoleHost'
    }
}

function New-AriaBufferState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Label,
        [ValidateRange(8,48)][int]$Width = 18,
        [ValidateRange(40,1000)][int]$IntervalMs = 90
    )

    [pscustomobject][ordered]@{
        label = $Label
        width = $Width
        intervalMs = $IntervalMs
        position = 0
        direction = 1
        tick = 0
        active = $true
        interactive = [bool](Test-AriaInteractiveBuffer)
        lastLength = 0
    }
}

function Get-AriaBufferFrame {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$State)

    $cells = New-Object 'System.Collections.Generic.List[string]'
    for ($index = 0; $index -lt [int]$State.width; $index++) {
        if ($index -eq [int]$State.position) {
            [void]$cells.Add('◆')
        }
        elseif ([math]::Abs($index - [int]$State.position) -eq 1) {
            [void]$cells.Add('·')
        }
        else {
            [void]$cells.Add('∙')
        }
    }

    $phase = @('∿','⌁','∿','⌁')[[int]$State.tick % 4]
    "{0}  {1}  ⟦{2}⟧" -f $phase,[string]$State.label,($cells -join '')
}

function Step-AriaBuffer {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$State)

    if (-not [bool]$State.active) { return $State }

    $next = [int]$State.position + [int]$State.direction
    if ($next -ge ([int]$State.width - 1)) {
        $next = [int]$State.width - 1
        [void]($State.direction = -1)
    }
    elseif ($next -le 0) {
        $next = 0
        [void]($State.direction = 1)
    }

    [void]($State.position = $next)
    [void]($State.tick = [int]$State.tick + 1)
    return $State
}

function Write-AriaBufferFrame {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$State)

    if (-not [bool]$State.interactive) { return }

    $frame = Get-AriaBufferFrame -State $State
    $padding = ''
    if ([int]$State.lastLength -gt $frame.Length) {
        $padding = ' ' * ([int]$State.lastLength - $frame.Length)
    }

    Write-Host ("`r" + $frame + $padding) -NoNewline -ForegroundColor Cyan
    [void]($State.lastLength = $frame.Length)
}

function Stop-AriaBuffer {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$State)

    [void]($State.active = $false)
    if ([bool]$State.interactive) {
        $clearWidth = [math]::Max([int]$State.lastLength,1)
        Write-Host ("`r" + (' ' * $clearWidth) + "`r") -NoNewline
    }
}
Export-ModuleMember -Function Invoke-AriaEtherPreview
# Alpha.12 universal buffering surface.
function New-AriaTransmissionBuffer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Label,
        [ValidateSet('local','remote','verification','runtime')][string]$Mode = 'local',
        [ValidateRange(10,36)][int]$Width = 18,
        [ValidateRange(45,500)][int]$IntervalMs = 85
    )

    [pscustomobject][ordered]@{
        label = $Label
        mode = $Mode
        width = $Width
        intervalMs = $IntervalMs
        tick = 0
        position = 0
        direction = 1
        active = $true
        interactive = [bool](Test-AriaInteractiveBuffer)
        lastLength = 0
        startedAt = [datetime]::UtcNow
    }
}

function Get-AriaTransmissionPhase {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$State)

    $cycle = [int]$State.tick % 16
    if ($cycle -lt 4) { return 'mesh' }
    if ($cycle -lt 9) { return 'transmit' }
    if ($cycle -lt 13) { return 'align' }
    return 'verify'
}

function Get-AriaGearGlyphs {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$State)

    $left = @('⚙','◈','⚙','◇')[[int]$State.tick % 4]
    $right = @('◇','⚙','◈','⚙')[[int]$State.tick % 4]
    [pscustomobject][ordered]@{
        left = $left
        right = $right
    }
}

function Get-AriaTransmissionFrame {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$State)

    $phase = Get-AriaTransmissionPhase -State $State
    $gears = Get-AriaGearGlyphs -State $State
    $cells = New-Object 'System.Collections.Generic.List[string]'

    for ($index = 0; $index -lt [int]$State.width; $index++) {
        $distance = [math]::Abs($index - [int]$State.position)

        if ($phase -eq 'mesh') {
            if ($distance -eq 0) { [void]$cells.Add('◆') }
            elseif ($distance -eq 1) { [void]$cells.Add('◇') }
            else { [void]$cells.Add('·') }
        }
        elseif ($phase -eq 'transmit') {
            if ($distance -eq 0) { [void]$cells.Add('⬢') }
            elseif (($index + [int]$State.tick) % 3 -eq 0) { [void]$cells.Add('∙') }
            else { [void]$cells.Add('·') }
        }
        elseif ($phase -eq 'align') {
            $centerLeft = [math]::Floor(([int]$State.width - 1) / 2)
            $centerRight = [math]::Ceiling(([int]$State.width - 1) / 2)
            if ($index -eq $centerLeft -or $index -eq $centerRight) { [void]$cells.Add('◈') }
            elseif ($distance -eq 0) { [void]$cells.Add('◇') }
            else { [void]$cells.Add('·') }
        }
        else {
            if ($index -eq [math]::Floor(([int]$State.width - 1) / 2)) { [void]$cells.Add('◆') }
            elseif ($index % 2 -eq 0) { [void]$cells.Add('─') }
            else { [void]$cells.Add('·') }
        }
    }

    $elapsed = [math]::Max(0,([datetime]::UtcNow - [datetime]$State.startedAt).TotalSeconds)
    "{0}{1} {2,-9} {3} ⟦{4}⟧ {5,4:N1}s" -f `
        $gears.left, `
        $gears.right, `
        $phase, `
        [string]$State.label, `
        ($cells -join ''), `
        $elapsed
}

function Step-AriaTransmissionBuffer {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$State)

    if (-not [bool]$State.active) { return $State }

    $phase = Get-AriaTransmissionPhase -State $State
    if ($phase -eq 'align' -or $phase -eq 'verify') {
        $target = [int][math]::Floor(([int]$State.width - 1) / 2)
        if ([int]$State.position -lt $target) {
            [void]($State.position = [int]$State.position + 1)
        }
        elseif ([int]$State.position -gt $target) {
            [void]($State.position = [int]$State.position - 1)
        }
    }
    else {
        $next = [int]$State.position + [int]$State.direction
        if ($next -ge ([int]$State.width - 1)) {
            $next = [int]$State.width - 1
            [void]($State.direction = -1)
        }
        elseif ($next -le 0) {
            $next = 0
            [void]($State.direction = 1)
        }
        [void]($State.position = $next)
    }

    [void]($State.tick = [int]$State.tick + 1)
    return $State
}

function Write-AriaTransmissionFrame {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$State)

    if (-not [bool]$State.interactive) { return }

    $frame = Get-AriaTransmissionFrame -State $State
    $padding = ''
    if ([int]$State.lastLength -gt $frame.Length) {
        $padding = ' ' * ([int]$State.lastLength - $frame.Length)
    }

    Write-Host ("`r" + $frame + $padding) -NoNewline -ForegroundColor Cyan
    [void]($State.lastLength = $frame.Length)
}

function Complete-AriaTransmissionBuffer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$State,
        [ValidateSet('PASS','REJECT','WARN','FAIL')][string]$Outcome = 'PASS'
    )

    [void]($State.active = $false)
    if (-not [bool]$State.interactive) { return }

    $center = [int][math]::Floor(([int]$State.width - 1) / 2)
    $cells = New-Object 'System.Collections.Generic.List[string]'
    for ($index = 0; $index -lt [int]$State.width; $index++) {
        if ($index -eq $center) { [void]$cells.Add('◆') }
        elseif ([math]::Abs($index - $center) -eq 1) { [void]$cells.Add('◈') }
        else { [void]$cells.Add('─') }
    }

    $glyph = if ($Outcome -eq 'PASS') { '◆' } elseif ($Outcome -eq 'REJECT') { '◇' } elseif ($Outcome -eq 'WARN') { '⬖' } else { '⬗' }
    $frame = "{0}  aligned   {1} ⟦{2}⟧" -f $glyph,[string]$State.label,($cells -join '')
    $padding = ''
    if ([int]$State.lastLength -gt $frame.Length) {
        $padding = ' ' * ([int]$State.lastLength - $frame.Length)
    }

    Write-Host ("`r" + $frame + $padding) -NoNewline -ForegroundColor Green
    Start-Sleep -Milliseconds 110
    Write-Host ("`r" + (' ' * [math]::Max([int]$State.lastLength,$frame.Length)) + "`r") -NoNewline
}

function Invoke-AriaBufferedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory=$true)][string]$WorkingDirectory,
        [Parameter(Mandatory=$true)][string]$Label,
        [ValidateSet('local','remote','verification','runtime')][string]$Mode = 'local',
        [switch]$VerboseBuffer
    )

    $stdout = [IO.Path]::GetTempFileName()
    $stderr = [IO.Path]::GetTempFileName()
    $buffer = New-AriaTransmissionBuffer -Label $Label -Mode $Mode

    try {
        $process = Start-Process `
            -FilePath $FilePath `
            -ArgumentList $ArgumentList `
            -WorkingDirectory $WorkingDirectory `
            -PassThru `
            -NoNewWindow `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr

        try {
            while (-not $process.HasExited) {
                Write-AriaTransmissionFrame -State $buffer
                Start-Sleep -Milliseconds ([int]$buffer.intervalMs)
                $null = Step-AriaTransmissionBuffer -State $buffer
                $process.Refresh()
            }

            $process.WaitForExit()
            $process.Refresh()
        }
        catch {
            Complete-AriaTransmissionBuffer -State $buffer -Outcome FAIL
            throw
        }

        $exitCode = [int]$process.ExitCode
        $outText = [IO.File]::ReadAllText($stdout)
        $errText = [IO.File]::ReadAllText($stderr)

        if ($VerboseBuffer -or $env:ARIA_VERBOSE -eq '1') {
            if ($outText) { Write-Host $outText.TrimEnd() -ForegroundColor DarkGray }
            if ($errText) { Write-Host $errText.TrimEnd() -ForegroundColor DarkGray }
        }

        $completedAt = [datetime]::UtcNow
        Complete-AriaTransmissionBuffer -State $buffer -Outcome $(if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' })

        $receipt = New-AriaTransmissionReceipt `
            -Label $Label `
            -Mode $Mode `
            -ExitCode $exitCode `
            -StartedAt ([datetime]$buffer.startedAt) `
            -CompletedAt $completedAt `
            -Stdout $outText `
            -Stderr $errText

        Write-AriaTransmissionReceipt -Receipt $receipt

        [pscustomobject][ordered]@{
            exitCode = $exitCode
            stdout = $outText
            stderr = $errText
            filePath = $FilePath
            arguments = @($ArgumentList)
            label = $Label
            mode = $Mode
            receipt = $receipt
        }
    }
    finally {
        Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
    }
}
Export-ModuleMember -Function `
    Test-AriaInteractiveBuffer, `
    New-AriaBufferState, `
    Get-AriaBufferFrame, `
    Step-AriaBuffer, `
    Write-AriaBufferFrame, `
    Stop-AriaBuffer
# Alpha.13 Bufferflow surface.
function New-AriaTransmissionReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Label,
        [Parameter(Mandatory=$true)][ValidateSet('local','remote','verification','runtime')][string]$Mode,
        [Parameter(Mandatory=$true)][int]$ExitCode,
        [Parameter(Mandatory=$true)][datetime]$StartedAt,
        [Parameter(Mandatory=$true)][datetime]$CompletedAt,
        [string]$Stdout = '',
        [string]$Stderr = ''
    )

    $durationMs = [math]::Max(0,[int][math]::Round(($CompletedAt - $StartedAt).TotalMilliseconds))
    $stdoutBytes = [Text.Encoding]::UTF8.GetByteCount([string]$Stdout)
    $stderrBytes = [Text.Encoding]::UTF8.GetByteCount([string]$Stderr)
    $totalBytes = $stdoutBytes + $stderrBytes
    $outcome = if ($ExitCode -eq 0) { 'PASS' } else { 'FAIL' }
    $coherence = if ($ExitCode -eq 0) { 'aligned' } else { 'fractured' }

    [pscustomobject][ordered]@{
        label = $Label
        mode = $Mode
        outcome = $outcome
        coherence = $coherence
        exitCode = $ExitCode
        durationMs = $durationMs
        stdoutBytes = $stdoutBytes
        stderrBytes = $stderrBytes
        totalBytes = $totalBytes
        startedAt = $StartedAt.ToUniversalTime().ToString('o',[Globalization.CultureInfo]::InvariantCulture)
        completedAt = $CompletedAt.ToUniversalTime().ToString('o',[Globalization.CultureInfo]::InvariantCulture)
    }
}

function Format-AriaTransmissionReceipt {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Receipt)

    $glyph = if ([string]$Receipt.outcome -eq 'PASS') { '└─ ∿' } else { '└─ ⬗' }
    $authority = switch ([string]$Receipt.mode) {
        'remote' { 'provider' }
        'verification' { 'verifier' }
        'runtime' { 'runtime' }
        default { 'local' }
    }

    "{0} {1} · {2} · {3}ms · {4}B · exit:{5}" -f `
        $glyph, `
        $authority, `
        [string]$Receipt.coherence, `
        [int]$Receipt.durationMs, `
        [int]$Receipt.totalBytes, `
        [int]$Receipt.exitCode
}

function Write-AriaTransmissionReceipt {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Receipt)

    $line = Format-AriaTransmissionReceipt -Receipt $Receipt
    $color = if ([string]$Receipt.outcome -eq 'PASS') { [ConsoleColor]::DarkCyan } else { [ConsoleColor]::Red }
    Write-Host $line -ForegroundColor $color
}

function Invoke-AriaBufferedItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][scriptblock]$Action,
        [ValidateSet('local','remote','verification','runtime')][string]$Mode = 'local',
        [switch]$VerboseBuffer
    )

    $startedAt = [datetime]::UtcNow
    $stdout = ''
    $stderr = ''
    $exitCode = 0

    $state = New-AriaTransmissionBuffer -Label $Name -Mode $Mode
    try {
        Write-AriaTransmissionFrame -State $state
        try {
            $output = & $Action 2>&1
            if ($null -ne $output) {
                $stdout = ($output | Out-String).TrimEnd()
            }
        }
        catch {
            $exitCode = 1
            $stderr = $_ | Out-String
        }

        $null = Step-AriaTransmissionBuffer -State $state
        Complete-AriaTransmissionBuffer -State $state -Outcome $(if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' })

        if ($VerboseBuffer -or $env:ARIA_VERBOSE -eq '1') {
            if ($stdout) { Write-Host $stdout -ForegroundColor DarkGray }
            if ($stderr) { Write-Host $stderr -ForegroundColor DarkGray }
        }

        $receipt = New-AriaTransmissionReceipt `
            -Label $Name `
            -Mode $Mode `
            -ExitCode $exitCode `
            -StartedAt $startedAt `
            -CompletedAt ([datetime]::UtcNow) `
            -Stdout $stdout `
            -Stderr $stderr

        Write-AriaTransmissionReceipt -Receipt $receipt

        if ($exitCode -ne 0) {
            throw $stderr.Trim()
        }

        [pscustomobject][ordered]@{
            name = $Name
            output = $stdout
            receipt = $receipt
        }
    }
    finally {
        [void]($state.active = $false)
    }
}

function Invoke-AriaBufferedSequence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object[]]$Items,
        [switch]$VerboseBuffer
    )

    $results = New-Object 'System.Collections.Generic.List[object]'
    foreach ($item in $Items) {
        if ($null -eq $item.name -or $null -eq $item.action) {
            throw 'Each buffered sequence item requires name and action.'
        }

        $mode = if ($null -ne $item.mode) { [string]$item.mode } else { 'local' }
        $result = Invoke-AriaBufferedItem `
            -Name ([string]$item.name) `
            -Action ([scriptblock]$item.action) `
            -Mode $mode `
            -VerboseBuffer:$VerboseBuffer

        [void]$results.Add($result)
    }

    return @($results.ToArray())
}
Export-ModuleMember -Function `
    New-AriaTransmissionBuffer, `
    Get-AriaTransmissionPhase, `
    Get-AriaGearGlyphs, `
    Get-AriaTransmissionFrame, `
    Step-AriaTransmissionBuffer, `
    Write-AriaTransmissionFrame, `
    Complete-AriaTransmissionBuffer, `
    Invoke-AriaBufferedProcess
# Alpha.14 Signalflow surface.
Export-ModuleMember -Function `
    New-AriaTransmissionReceipt, `
    Format-AriaTransmissionReceipt, `
    Write-AriaTransmissionReceipt, `
    Invoke-AriaBufferedItem, `
    Invoke-AriaBufferedSequence