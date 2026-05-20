param(
    [Parameter(Mandatory = $false)]
    [string]$TargetPath = ".\test_delete_sandbox",

    [Parameter(Mandatory = $false)]
    [switch]$Execute
)

$ErrorActionPreference = "Stop"

function Resolve-SafePath {
    param([string]$PathText)
    $resolved = Resolve-Path -LiteralPath $PathText -ErrorAction Stop
    return $resolved.Path
}

try {
    $fullTarget = Resolve-SafePath -PathText $TargetPath
} catch {
    Write-Host "[ERROR] Target path not found: $TargetPath"
    exit 1
}

$cwd = (Get-Location).Path
$fullCwd = (Resolve-Path -LiteralPath $cwd).Path

# Safety guard: only allow deletion inside current working directory.
if (-not $fullTarget.StartsWith($fullCwd, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "[ERROR] Refuse to delete path outside current directory."
    Write-Host "  CWD    : $fullCwd"
    Write-Host "  Target : $fullTarget"
    exit 2
}

Write-Host "[INFO] CWD    : $fullCwd"
Write-Host "[INFO] Target : $fullTarget"

$items = Get-ChildItem -LiteralPath $fullTarget -Recurse -Force -ErrorAction SilentlyContinue
$count = ($items | Measure-Object).Count
Write-Host "[INFO] Recursive item count: $count"

if (-not $Execute) {
    Write-Host "[DRY-RUN] No deletion performed."
    Write-Host "[DRY-RUN] Add -Execute to actually remove files/folders."
    $items | Select-Object FullName | Format-Table -AutoSize
    exit 0
}

Write-Host "[EXECUTE] Removing target recursively..."
Remove-Item -LiteralPath $fullTarget -Recurse -Force -ErrorAction Stop
Write-Host "[OK] Deleted: $fullTarget"

