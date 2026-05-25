param(
    [Parameter(Mandatory = $true)][string]$TargetHost,
    [Parameter(Mandatory = $true)][int]$Port,
    [Parameter(Mandatory = $false)][int]$ConnectTimeoutMs = 800
)

$ErrorActionPreference = "Stop"
$client = $null
try {
    $timeout = [Math]::Max(100, $ConnectTimeoutMs)
    $client = New-Object Net.Sockets.TcpClient
    $iar = $client.BeginConnect($TargetHost, $Port, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($timeout)) {
        exit 2
    }

    $client.EndConnect($iar)
    exit 0
}
catch {
    exit 1
}
finally {
    try { if ($client) { $client.Close() } } catch {}
}
