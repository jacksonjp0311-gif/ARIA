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
Export-ModuleMember -Function `
    Test-AriaInteractiveBuffer, `
    New-AriaBufferState, `
    Get-AriaBufferFrame, `
    Step-AriaBuffer, `
    Write-AriaBufferFrame, `
    Stop-AriaBuffer
