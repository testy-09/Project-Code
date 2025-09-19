param(
    [Parameter(Mandatory=$false)]
    [string]$Program = "HelloWorld",

    # Accept either an array of strings for positional args or a hashtable for named args (splat)
    [Parameter(Mandatory=$false)]
    [object]$ArgsForProgram
)

$root = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$programPath = Join-Path $root $Program
$main = Join-Path $programPath "main.ps1"

if (-not (Test-Path $main)) {
    Write-Error "Program '$Program' not found. Available programs:"
    Get-ChildItem -Directory -Path $root | ForEach-Object { Write-Host " - $($_.Name)" }
    exit 1
}

Write-Host "Launching program: $Program" -ForegroundColor Cyan

# If the caller passed a hashtable, splat it as named params. If array, pass as positional args.
if ($ArgsForProgram -is [hashtable]) {
    & $main @ArgsForProgram
} elseif ($ArgsForProgram -is [object[]] -or $ArgsForProgram -is [array]) {
    & $main @($ArgsForProgram)
} elseif ($null -ne $ArgsForProgram) {
    # Single scalar value
    & $main $ArgsForProgram
} else {
    & $main
}
