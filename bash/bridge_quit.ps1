param(
    [Parameter(Mandatory = $true)][string]$Host,
    [Parameter(Mandatory = $true)][int]$Port,
    [Parameter(Mandatory = $false)][int]$ConnectTimeoutMs = 1500,
    [Parameter(Mandatory = $false)][switch]$ReadReply
)

$ErrorActionPreference = "Stop"
$client = $null
$stream = $null
$writer = $null
$reader = $null

try {
    $timeout = [Math]::Max(100, $ConnectTimeoutMs)
    $client = New-Object Net.Sockets.TcpClient
    $iar = $client.BeginConnect($Host, $Port, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($timeout)) {
        exit 2
    }

    $client.EndConnect($iar)
    $stream = $client.GetStream()
    $stream.ReadTimeout = $timeout
    $stream.WriteTimeout = $timeout

    $writer = New-Object IO.StreamWriter($stream)
    $writer.AutoFlush = $true
    $writer.WriteLine('{"cmd":"quit"}')

    if ($ReadReply.IsPresent) {
        $reader = New-Object IO.StreamReader($stream)
        [void]$reader.ReadLine()
    }

    exit 0
}
catch {
    exit 1
}
finally {
    try { if ($reader) { $reader.Dispose() } } catch {}
    try { if ($writer) { $writer.Dispose() } } catch {}
    try { if ($stream) { $stream.Dispose() } } catch {}
    try { if ($client) { $client.Close() } } catch {}
}
