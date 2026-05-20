param(
    [Parameter(Mandatory = $true)][string]$HostName,
    [Parameter(Mandatory = $true)][int]$Port,
    [string]$Prompt = "tpose",
    [double]$Duration = 5.0,
    [int]$Seed = 42,
    [int]$DiffusionSteps = 100,
    [string]$ConstraintsJson = ""
)

$ErrorActionPreference = "Stop"

function Send-Line {
    param(
        [System.IO.StreamWriter]$Writer,
        [object]$Obj
    )
    $Writer.WriteLine(($Obj | ConvertTo-Json -Compress))
}

$client = $null
$stream = $null
$writer = $null
$reader = $null
$maxGenerateWaitMinutes = 30

try {
    $client = New-Object Net.Sockets.TcpClient($HostName, $Port)
    $stream = $client.GetStream()
    $writer = New-Object IO.StreamWriter($stream)
    $writer.AutoFlush = $true
    $reader = New-Object IO.StreamReader($stream)

    $deadline = (Get-Date).AddMinutes(10)
    while ($true) {
        Send-Line -Writer $writer -Obj @{ cmd = "ping" }
        $line = $reader.ReadLine()
        if ($null -eq $line) { throw "Bridge closed connection during ping." }
        Write-Output $line
        $obj = $line | ConvertFrom-Json
        if ($obj.status -eq "error") {
            try { Send-Line -Writer $writer -Obj @{ cmd = "quit" } } catch {}
            throw ("Bridge ping error: " + $line)
        }
        if ($obj.status -eq "pong" -or $obj.status -eq "ready") { break }
        if ((Get-Date) -gt $deadline) { throw "Timeout waiting for model ready." }
        Start-Sleep -Seconds 1
    }

    Send-Line -Writer $writer -Obj @{
        cmd = "generate"
        prompt = $Prompt
        duration = $Duration
        seed = $Seed
        diffusion_steps = $DiffusionSteps
        constraints_json = $ConstraintsJson
    }

    $done = $false
    $doneDeadline = (Get-Date).AddMinutes($maxGenerateWaitMinutes)
    while (($line = $reader.ReadLine()) -ne $null) {
        Write-Output $line
        $obj = $line | ConvertFrom-Json
        if ($obj.status -eq "error") {
            try { Send-Line -Writer $writer -Obj @{ cmd = "quit" } } catch {}
            throw ("Bridge generate error: " + $line)
        }
        if ($obj.status -eq "done") {
            $done = $true
            break
        }
        if ((Get-Date) -gt $doneDeadline) {
            try { Send-Line -Writer $writer -Obj @{ cmd = "quit" } } catch {}
            throw "Timeout waiting for generate done."
        }
    }
    if (-not $done) { throw "Bridge closed connection before done." }

    try {
        Send-Line -Writer $writer -Obj @{ cmd = "quit" }
    }
    catch {
        # Some server exits close socket immediately after done.
        return
    }

    while ($true) {
        try {
            $line = $reader.ReadLine()
        }
        catch {
            # Treat post-done disconnect as normal shutdown.
            break
        }
        if ($null -eq $line) { break }
        Write-Output $line
        $obj = $line | ConvertFrom-Json
        if ($obj.status -eq "bye") { break }
    }
}
finally {
    if ($reader) { $reader.Close() }
    if ($writer) { $writer.Close() }
    if ($stream) { $stream.Close() }
    if ($client) { $client.Close() }
}
