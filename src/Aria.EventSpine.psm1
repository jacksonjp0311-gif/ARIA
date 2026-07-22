Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:AriaEventSequence = 0
$script:AriaEventBuffer = New-Object System.Collections.Generic.List[object]
$script:AriaEventSubscribers = New-Object System.Collections.Generic.List[scriptblock]
$script:AriaEventWorkspace = $null
$script:AriaEventProfile = 'compact'
$script:AriaEventPersist = $false

function Initialize-AriaEventSpine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$WorkspaceRoot,
        [string]$Profile = 'compact',
        [switch]$Persist
    )

    $script:AriaEventWorkspace = [IO.Path]::GetFullPath($WorkspaceRoot)
    $script:AriaEventProfile = $Profile
    $script:AriaEventPersist = [bool]$Persist
    $script:AriaEventSequence = 0
    $script:AriaEventBuffer.Clear()
    $script:AriaEventSubscribers.Clear()

    if ($script:AriaEventPersist) {
        $folder = Join-Path $script:AriaEventWorkspace '.aria/events'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    [pscustomobject][ordered]@{
        format = 'aria.event-spine'
        version = 1
        workspace = $script:AriaEventWorkspace
        profile = $script:AriaEventProfile
        persistent = $script:AriaEventPersist
    }
}

function Get-AriaEventDigest {
    param([Parameter(Mandatory=$true)]$Event)

    $body = [pscustomobject][ordered]@{
        format = [string]$Event.format
        version = [int]$Event.version
        sequence = [int]$Event.sequence
        domain = [string]$Event.domain
        phase = [string]$Event.phase
        state = [string]$Event.state
        energy = [string]$Event.energy
        information = [string]$Event.information
        coherence = [string]$Event.coherence
        source = [string]$Event.source
        occurredAt = [string]$Event.occurredAt
        data = $Event.data
    }
    $json = ConvertTo-AriaJson -Value $body
    Get-AriaSha256Bytes -Bytes ([Text.Encoding]::UTF8.GetBytes($json))
}

function New-AriaEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidatePattern('^[a-z][a-z0-9._-]*$')][string]$Domain,
        [Parameter(Mandatory=$true)][ValidatePattern('^[a-z][a-z0-9._-]*$')][string]$Phase,
        [ValidateSet('ACTIVE','PASS','REJECT','WARN','FAIL','INFO')][string]$State = 'INFO',
        [Parameter(Mandatory=$true)][string]$Energy,
        [Parameter(Mandatory=$true)][string]$Information,
        [Parameter(Mandatory=$true)][string]$Coherence,
        [string]$Source = 'aria.runtime',
        $Data = $null,
        [datetime]$OccurredAt = ([datetime]::UtcNow)
    )

    $script:AriaEventSequence++
    $event = [pscustomobject][ordered]@{
        format = 'aria.event'
        version = 1
        sequence = $script:AriaEventSequence
        domain = $Domain.ToLowerInvariant()
        phase = $Phase.ToLowerInvariant()
        state = $State.ToUpperInvariant()
        energy = $Energy
        information = $Information
        coherence = $Coherence
        source = $Source
        occurredAt = $OccurredAt.ToUniversalTime().ToString('o')
        data = $Data
        digest = ''
    }
    $event.digest = Get-AriaEventDigest -Event $event
    $event
}

function Test-AriaEvent {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Event)

    $errors = New-Object System.Collections.Generic.List[string]
    if ([string]$Event.format -ne 'aria.event') { $errors.Add('format must be aria.event') }
    if ([int]$Event.version -ne 1) { $errors.Add('version must be 1') }
    if ([int]$Event.sequence -lt 1) { $errors.Add('sequence must be positive') }
    if ([string]$Event.domain -notmatch '^[a-z][a-z0-9._-]*$') { $errors.Add('domain is invalid') }
    if ([string]$Event.phase -notmatch '^[a-z][a-z0-9._-]*$') { $errors.Add('phase is invalid') }
    if ([string]$Event.state -notin @('ACTIVE','PASS','REJECT','WARN','FAIL','INFO')) { $errors.Add('state is invalid') }

    $expected = ''
    try { $expected = Get-AriaEventDigest -Event $Event }
    catch { $errors.Add($_.Exception.Message) }
    if ($expected -and [string]$Event.digest -ne $expected) { $errors.Add('digest mismatch') }

    [pscustomobject][ordered]@{
        valid = ($errors.Count -eq 0)
        errors = @($errors)
        digest = $expected
    }
}

function Register-AriaEventSubscriber {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][scriptblock]$Handler)
    $script:AriaEventSubscribers.Add($Handler)
    $script:AriaEventSubscribers.Count
}

function ConvertTo-AriaEtherEvent {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Event)

    [pscustomobject][ordered]@{
        phase = ("{0}.{1}" -f $Event.domain,$Event.phase)
        name = $Event.source
        state = $Event.state
        energy = $Event.energy
        information = $Event.information
        coherence = $Event.coherence
    }
}

function Publish-AriaEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Event,
        [switch]$Render,
        [switch]$PassThru
    )

    $verification = Test-AriaEvent -Event $Event
    if (-not $verification.valid) { throw ('ARIA event rejected: ' + ($verification.errors -join '; ')) }

    $script:AriaEventBuffer.Add($Event)

    if ($script:AriaEventPersist -and $script:AriaEventWorkspace) {
        $folder = Join-Path $script:AriaEventWorkspace '.aria/events'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $ledger = Join-Path $folder 'aria.events.ndjson'
        $json = $Event | ConvertTo-Json -Depth 100 -Compress
        [IO.File]::AppendAllText($ledger,$json + [Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    }

    foreach ($subscriber in $script:AriaEventSubscribers.ToArray()) {
        & $subscriber $Event
    }

    if ($Render) {
        $ether = ConvertTo-AriaEtherEvent -Event $Event
        Write-AriaTriadicTransmission -Event $ether -Profile $script:AriaEventProfile
    }

    if ($PassThru) { $Event }
}

function Send-AriaEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Domain,
        [Parameter(Mandatory=$true)][string]$Phase,
        [ValidateSet('ACTIVE','PASS','REJECT','WARN','FAIL','INFO')][string]$State = 'INFO',
        [Parameter(Mandatory=$true)][string]$Energy,
        [Parameter(Mandatory=$true)][string]$Information,
        [Parameter(Mandatory=$true)][string]$Coherence,
        [string]$Source = 'aria.runtime',
        $Data = $null,
        [switch]$Render,
        [switch]$PassThru
    )

    $event = New-AriaEvent -Domain $Domain -Phase $Phase -State $State -Energy $Energy -Information $Information -Coherence $Coherence -Source $Source -Data $Data
    Publish-AriaEvent -Event $event -Render:$Render -PassThru:$PassThru
}

function Get-AriaEventBuffer {
    [CmdletBinding()]
    param()
    $script:AriaEventBuffer.ToArray()
}

function Read-AriaEventLedger {
    [CmdletBinding()]
    param([string]$WorkspaceRoot = $script:AriaEventWorkspace)

    if (-not $WorkspaceRoot) { return @() }
    $ledger = Join-Path ([IO.Path]::GetFullPath($WorkspaceRoot)) '.aria/events/aria.events.ndjson'
    if (-not (Test-Path -LiteralPath $ledger -PathType Leaf)) { return @() }

    $events = New-Object System.Collections.Generic.List[object]
    foreach ($line in Get-Content -LiteralPath $ledger -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $event = $line | ConvertFrom-Json
        $verification = Test-AriaEvent -Event $event
        if (-not $verification.valid) { throw ('ARIA event ledger rejected: ' + ($verification.errors -join '; ')) }
        $events.Add($event)
    }
    $events.ToArray()
}

Export-ModuleMember -Function Initialize-AriaEventSpine,New-AriaEvent,Test-AriaEvent,Register-AriaEventSubscriber,ConvertTo-AriaEtherEvent,Publish-AriaEvent,Send-AriaEvent,Get-AriaEventBuffer,Read-AriaEventLedger