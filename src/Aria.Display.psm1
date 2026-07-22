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

Export-ModuleMember -Function Write-AriaPaint, Write-AriaBanner, Write-AriaStage, Write-AriaTreeStage, Write-AriaTreeText, Write-AriaTrunk, Write-AriaKeyValue, Write-AriaSummary, Write-AriaStream, Format-AriaDuration

function Invoke-AriaEtherPreview {
    param([Parameter(Mandatory=$true)]$Transmission)

    $events = Get-AriaTriadicEventsFromTransmission -Transmission $Transmission
    foreach ($event in $events) {
        Write-AriaTriadicTransmission -Event $event
    }
}

Export-ModuleMember -Function Invoke-AriaEtherPreview