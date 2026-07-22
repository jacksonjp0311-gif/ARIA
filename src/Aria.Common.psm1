Set-StrictMode -Version 2.0

function Get-AriaRepositoryRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

function Read-AriaUtf8Text {
    param([Parameter(Mandatory=$true)][string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    return [System.IO.File]::ReadAllText($resolved, $encoding)
}

function Get-AriaCompilerVersion {
    $versionPath = Join-Path (Get-AriaRepositoryRoot) 'VERSION'
    return ((Read-AriaUtf8Text -Path $versionPath).Trim())
}

function Get-AriaLock {
    param([string]$Root = (Get-AriaRepositoryRoot))
    $path = Join-Path $Root 'aria.lock.json'
    return (Read-AriaUtf8Text -Path $path | ConvertFrom-Json)
}

function Normalize-AriaText {
    param([Parameter(Mandatory=$true)][string]$Text)
    $newlines = (($Text -replace "`r`n", "`n") -replace "`r", "`n")
    return $newlines.Normalize([System.Text.NormalizationForm]::FormC)
}

function Get-AriaSourceText {
    param([Parameter(Mandatory=$true)][string]$Path)
    return (Normalize-AriaText -Text (Read-AriaUtf8Text -Path $Path))
}

function Write-AriaUtf8NoBom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Text
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Get-AriaSha256Bytes {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($Bytes)
        return ([System.BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant())
    }
    finally {
        $sha.Dispose()
    }
}

function Get-AriaSha256Text {
    param([Parameter(Mandatory=$true)][string]$Text)
    $encoding = New-Object System.Text.UTF8Encoding($false)
    return (Get-AriaSha256Bytes -Bytes ($encoding.GetBytes((Normalize-AriaText -Text $Text))))
}

function Get-AriaSha256File {
    param([Parameter(Mandatory=$true)][string]$Path)
    return (Get-AriaSha256Bytes -Bytes ([System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)))
}

function ConvertTo-AriaJsonString {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return 'null' }
    $builder = New-Object System.Text.StringBuilder
    $null = $builder.Append('"')
    foreach ($character in $Text.ToCharArray()) {
        $code = [int][char]$character
        switch ($code) {
            8  { $null = $builder.Append('\b'); continue }
            9  { $null = $builder.Append('\t'); continue }
            10 { $null = $builder.Append('\n'); continue }
            12 { $null = $builder.Append('\f'); continue }
            13 { $null = $builder.Append('\r'); continue }
            34 { $null = $builder.Append('\"'); continue }
            92 { $null = $builder.Append('\\'); continue }
        }
        if ($code -lt 32) {
            $null = $builder.Append(('\u{0:x4}' -f $code))
        }
        else {
            $null = $builder.Append($character)
        }
    }
    $null = $builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-AriaJsonNumber {
    param([Parameter(Mandatory=$true)]$Value)
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Value -is [double]) {
        if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) { throw 'ARIA canonical JSON rejects NaN and infinity.' }
        return $Value.ToString('R', $culture)
    }
    if ($Value -is [single]) {
        if ([single]::IsNaN($Value) -or [single]::IsInfinity($Value)) { throw 'ARIA canonical JSON rejects NaN and infinity.' }
        return $Value.ToString('R', $culture)
    }
    return $Value.ToString($culture)
}

function ConvertTo-AriaJsonValue {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [string] -or $Value -is [char]) { return (ConvertTo-AriaJsonString -Text ([string]$Value)) }
    if ($Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
        return (ConvertTo-AriaJsonNumber -Value $Value)
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = @($Value.Keys)
        if (-not ($Value -is [System.Collections.Specialized.OrderedDictionary])) {
            [string[]]$keys = @($keys | ForEach-Object { [string]$_ })
            [Array]::Sort($keys, [System.StringComparer]::Ordinal)
        }
        $pairs = New-Object System.Collections.Generic.List[string]
        foreach ($key in $keys) {
            $pairs.Add((ConvertTo-AriaJsonString -Text ([string]$key)) + ':' + (ConvertTo-AriaJsonValue -Value $Value[$key]))
        }
        return '{' + ($pairs -join ',') + '}'
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $pairs = New-Object System.Collections.Generic.List[string]
        foreach ($property in $Value.PSObject.Properties) {
            $pairs.Add((ConvertTo-AriaJsonString -Text $property.Name) + ':' + (ConvertTo-AriaJsonValue -Value $property.Value))
        }
        return '{' + ($pairs -join ',') + '}'
    }
    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        $items = New-Object System.Collections.Generic.List[string]
        foreach ($item in $Value) { $items.Add((ConvertTo-AriaJsonValue -Value $item)) }
        return '[' + ($items -join ',') + ']'
    }
    throw "ARIA canonical JSON cannot encode type '$($Value.GetType().FullName)'."
}

function ConvertTo-AriaJson {
    param([Parameter(Mandatory=$true)]$Value)
    return (ConvertTo-AriaJsonValue -Value $Value)
}

function ConvertTo-AriaHashtable {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $table = @{}
        foreach ($key in $Value.Keys) {
            $table[[string]$key] = ConvertTo-AriaHashtable -Value $Value[$key]
        }
        return $table
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $table = @{}
        foreach ($property in $Value.PSObject.Properties) {
            $table[$property.Name] = ConvertTo-AriaHashtable -Value $property.Value
        }
        return $table
    }
    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        $items = @()
        foreach ($item in $Value) { $items += ,(ConvertTo-AriaHashtable -Value $item) }
        return ,$items
    }
    return $Value
}

function Test-AriaSemanticVersion {
    param([Parameter(Mandatory=$true)][string]$Version)
    $core = '(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
    $identifier = '(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)'
    $preRelease = '(?:-' + $identifier + '(?:\.' + $identifier + ')*)?'
    $build = '(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?'
    return [bool]($Version -match ('^' + $core + $preRelease + $build + '$'))
}

function New-AriaDiagnostic {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('error','warning','info')][string]$Severity,
        [Parameter(Mandatory=$true)][string]$Code,
        [Parameter(Mandatory=$true)][string]$Message,
        [int]$Line = 0
    )
    return [pscustomobject][ordered]@{
        severity = $Severity
        code = $Code
        message = $Message
        line = $Line
    }
}

function Get-AriaErrorDiagnostics {
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()]$Diagnostics)
    [object[]]$errors = @($Diagnostics | Where-Object { $_.severity -eq 'error' })
    return ,$errors
}

function Get-AriaPathComparison {
    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        return [System.StringComparison]::OrdinalIgnoreCase
    }
    return [System.StringComparison]::Ordinal
}

function Resolve-AriaConfinedPath {
    param(
        [Parameter(Mandatory=$true)][string]$WorkspaceRoot,
        [Parameter(Mandatory=$true)][string]$Scope,
        [Parameter(Mandatory=$true)][string]$RequestedPath
    )
    $root = [System.IO.Path]::GetFullPath($WorkspaceRoot)
    $scopeRoot = [System.IO.Path]::GetFullPath((Join-Path $root $Scope))
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $scopeRoot $RequestedPath))
    $comparison = Get-AriaPathComparison
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $rootPrefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + $separator
    $scopePrefix = $scopeRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + $separator
    if (-not ($scopeRoot + $separator).StartsWith($rootPrefix, $comparison)) {
        throw "ARIA capability scope escapes the workspace: $Scope"
    }
    if (-not ($candidate + $separator).StartsWith($rootPrefix, $comparison)) {
        throw "ARIA path escapes the workspace: $RequestedPath"
    }
    if (-not ($candidate + $separator).StartsWith($scopePrefix, $comparison)) {
        throw "ARIA path escapes capability scope '$Scope': $RequestedPath"
    }

    $relative = $candidate.Substring($root.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $cursor = $root
    foreach ($segment in ($relative -split '[\\/]')) {
        if (-not $segment) { continue }
        $cursor = Join-Path $cursor $segment
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "ARIA path crosses a symbolic link or reparse point: $cursor"
            }
        }
    }
    return $candidate
}

function Get-AriaManifestEntries {
    param([string]$Root = (Get-AriaRepositoryRoot))
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([char]47, [char]92)
    $hashes = @{}
    foreach ($item in Get-ChildItem -LiteralPath $rootFull -Recurse -Force | Where-Object { -not $_.PSIsContainer }) {
        $relative = $item.FullName.Substring($rootFull.Length).TrimStart([char]47, [char]92).Replace([char]92, [char]47)
        if ($relative -eq 'MANIFEST.sha256') { continue }
        if ($relative -match '^(\.git|\.aria|dist)/') { continue }
        $hashes[$relative] = Get-AriaSha256File -Path $item.FullName
    }
    [string[]]$paths = @($hashes.Keys)
    [Array]::Sort($paths, [System.StringComparer]::Ordinal)
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($path in $paths) {
        $entries.Add([pscustomobject][ordered]@{ path = $path; hash = $hashes[$path] })
    }
    return $entries.ToArray()
}

function Update-AriaManifest {
    param([string]$Root = (Get-AriaRepositoryRoot))
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($entry in Get-AriaManifestEntries -Root $Root) {
        $lines.Add("$($entry.hash)  $($entry.path)")
    }
    $text = ($lines -join "`n") + "`n"
    Write-AriaUtf8NoBom -Path (Join-Path $Root 'MANIFEST.sha256') -Text $text
    return $lines.Count
}

function Test-AriaManifest {
    param([string]$Root = (Get-AriaRepositoryRoot))
    $manifestPath = Join-Path $Root 'MANIFEST.sha256'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        return [pscustomobject][ordered]@{ valid = $false; message = 'MANIFEST.sha256 is missing.'; expected = 0; actual = 0 }
    }
    $expected = [ordered]@{}
    foreach ($line in (Normalize-AriaText -Text (Read-AriaUtf8Text -Path $manifestPath)).Split("`n")) {
        if (-not $line) { continue }
        if ($line -notmatch '^([0-9a-f]{64})  (.+)$') {
            return [pscustomobject][ordered]@{ valid = $false; message = "Malformed manifest line: $line"; expected = 0; actual = 0 }
        }
        $expected[$matches[2]] = $matches[1]
    }
    $actualEntries = Get-AriaManifestEntries -Root $Root
    $actual = @{}
    foreach ($entry in $actualEntries) { $actual[$entry.path] = $entry.hash }
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($path in $expected.Keys) {
        if (-not $actual.ContainsKey($path)) { $problems.Add("missing:$path"); continue }
        if ($actual[$path] -ne $expected[$path]) { $problems.Add("changed:$path") }
    }
    foreach ($path in $actual.Keys) {
        if (-not $expected.Contains($path)) { $problems.Add("untracked:$path") }
    }
    $manifestMessage = 'manifest verified'
    if ($problems.Count -ne 0) { $manifestMessage = $problems -join ', ' }
    return [pscustomobject][ordered]@{
        valid = ($problems.Count -eq 0)
        message = $manifestMessage
        expected = $expected.Count
        actual = $actual.Count
    }
}

Export-ModuleMember -Function Get-AriaRepositoryRoot, Read-AriaUtf8Text, Get-AriaCompilerVersion, Get-AriaLock, Normalize-AriaText, Get-AriaSourceText, Write-AriaUtf8NoBom, Get-AriaSha256Bytes, Get-AriaSha256Text, Get-AriaSha256File, ConvertTo-AriaJson, ConvertTo-AriaHashtable, Test-AriaSemanticVersion, New-AriaDiagnostic, Get-AriaErrorDiagnostics, Resolve-AriaConfinedPath, Get-AriaManifestEntries, Update-AriaManifest, Test-AriaManifest
