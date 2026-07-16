[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CfstPath,

    [ValidateRange(1, 1000)]
    [int]$LatencyLimit = 300,

    [ValidateRange(1, 60)]
    [int]$DownloadTestSeconds = 6,

    [switch]$NoPush
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    $root = Split-Path -Parent $PSCommandPath
    if (-not (Test-Path (Join-Path $root '.git'))) {
        throw 'This folder is not a Git repository. Complete the "首次准备" steps in README.md first.'
    }
    return $root
}

function Convert-ToNumber {
    param([string]$Value)
    return [double]::Parse($Value.Trim(), [Globalization.CultureInfo]::InvariantCulture)
}

$repoRoot = Get-RepoRoot
$cfstFullPath = [IO.Path]::GetFullPath((Join-Path $repoRoot $CfstPath))
if (-not (Test-Path $cfstFullPath)) {
    throw "cfst.exe was not found: $cfstFullPath"
}

$resultPath = Join-Path $repoRoot 'result.csv'
$top5Path = Join-Path $repoRoot 'public/cf-top5.txt'
$jsonPath = Join-Path $repoRoot 'public/cf-top5.json'

# -dn 20 gives the tool enough low-latency candidates to rank a useful Top 5.
# -tlr 0 excludes any packet loss. Results are already sorted by speed by CFST.
Write-Host 'Running CloudflareSpeedTest on this computer...'
Push-Location (Split-Path -Parent $cfstFullPath)
try {
    # Run in cfst.exe's folder so its adjacent ip.txt is used.
    & $cfstFullPath -tl $LatencyLimit -tlr 0 -dn 20 -dt $DownloadTestSeconds -o $resultPath -p 5
    if ($LASTEXITCODE -ne 0) {
        throw "CloudflareSpeedTest failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
if (-not (Test-Path $resultPath)) {
    throw 'CloudflareSpeedTest did not create result.csv.'
}

# CFST result headers may be Chinese or English. We use column positions, which
# are stable: IP, Sent, Received, Loss, Latency, Download speed, Colo.
$rows = Get-Content -LiteralPath $resultPath -Encoding UTF8 |
    Select-Object -Skip 1 |
    Where-Object { $_.Trim() -ne '' } |
    ForEach-Object {
        $parts = $_ -split ','
        if ($parts.Count -lt 6) { return }
        $ip = $parts[0].Trim()
        $parsedIp = $null
        if (-not [Net.IPAddress]::TryParse($ip, [ref]$parsedIp)) { return }
        if ($parsedIp.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { return }

        try {
            [PSCustomObject]@{
                ip = $ip
                packet_loss = Convert-ToNumber $parts[3]
                latency_ms = Convert-ToNumber $parts[4]
                download_mbps = Convert-ToNumber $parts[5]
                colo = if ($parts.Count -ge 7) { $parts[6].Trim() } else { $null }
            }
        }
        catch {
            Write-Warning "Skipping unparsable line: $_"
        }
    } |
    Where-Object { $_.packet_loss -eq 0 -and $_.download_mbps -gt 0 } |
    Sort-Object -Property @{ Expression = 'download_mbps'; Descending = $true }, @{ Expression = 'latency_ms'; Descending = $false } |
    Select-Object -First 5

if (@($rows).Count -eq 0) {
    throw 'No zero-loss IPv4 result with a non-zero download speed was found. Check result.csv or relax the test conditions.'
}
if (@($rows).Count -lt 5) {
    Write-Warning "Only $(@($rows).Count) eligible IP(s) were found; publishing all available results."
}

$generatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$text = @($rows | ForEach-Object { "$($_.ip):443" }) -join [Environment]::NewLine
[IO.File]::WriteAllText($top5Path, $text + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

$payload = [ordered]@{
    generated_at = $generatedAt
    source = 'XIU2/CloudflareSpeedTest; tested locally on the publisher device'
    criteria = [ordered]@{
        count = 5
        port = 443
        packet_loss = 0
        sort = @('download_mbps_desc', 'latency_ms_asc')
    }
    nodes = @($rows | ForEach-Object {
        [ordered]@{
            address = $_.ip
            endpoint = "$($_.ip):443"
            download_mbps = $_.download_mbps
            latency_ms = $_.latency_ms
            colo = $_.colo
        }
    })
}
$payload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

Write-Host "Generated $(@($rows).Count) endpoint(s):"
$rows | ForEach-Object { Write-Host "  $($_.ip):443  $($_.download_mbps) MB/s  $($_.latency_ms) ms  $($_.colo)" }

Push-Location $repoRoot
try {
    git add public/cf-top5.txt public/cf-top5.json
    $pending = git status --porcelain -- public/cf-top5.txt public/cf-top5.json
    if (-not $pending) {
        Write-Host 'No Top 5 file changes to commit.'
        return
    }

    git commit -m "Update Cloudflare Top 5 ($generatedAt)"
    if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }

    if ($NoPush) {
        Write-Host 'Committed locally. -NoPush was set, so nothing was pushed.'
    }
    else {
        git push
        if ($LASTEXITCODE -ne 0) { throw 'git push failed. Check your GitHub remote and sign-in.' }
        Write-Host 'Published successfully.'
    }
}
finally {
    Pop-Location
}
