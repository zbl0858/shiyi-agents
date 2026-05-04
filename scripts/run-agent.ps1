[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet(
        'daily-briefing',
        'orchestrator',
        'task-manager',
        'agent-selector',
        'agent-copywriter',
        'agent-packager',
        'content-pipeline',
        'preview-content'
    )]
    [string]$ScriptName,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ScriptArgs = @(),

    [switch]$DryRun,
    [switch]$List
)

$scriptMap = [ordered]@{
    'daily-briefing'   = 'daily-briefing.sh'
    'orchestrator'     = 'orchestrator.sh'
    'task-manager'     = 'task-manager.sh'
    'agent-selector'   = 'agent-selector.sh'
    'agent-copywriter' = 'agent-copywriter.sh'
    'agent-packager'   = 'agent-packager.sh'
    'content-pipeline' = 'content-pipeline.sh'
    'preview-content'  = 'preview-content.sh'
}

if ($List) {
    $scriptMap.Keys
    exit 0
}

if (-not $ScriptName) {
    Write-Error 'Missing script name. Use -List to see available scripts.'
    exit 1
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot $scriptMap[$ScriptName]

if (-not (Test-Path -LiteralPath $scriptPath)) {
    Write-Error "Script not found: $scriptPath"
    exit 1
}

function Quote-BashArg {
    param([Parameter(Mandatory = $true)][string]$Value)

    $escapedSingleQuote = "'`"'`"'"
    return "'" + ($Value -replace "'", $escapedSingleQuote) + "'"
}

function Convert-ToWslPath {
    param([Parameter(Mandatory = $true)][string]$WindowsPath)

    $resolved = (Resolve-Path -LiteralPath $WindowsPath).Path
    if ($resolved -match '^(?<drive>[A-Za-z]):\\(?<rest>.*)$') {
        $drive = $Matches.drive.ToLowerInvariant()
        $rest = ($Matches.rest -replace '\\', '/')
        return "/mnt/$drive/$rest"
    }

    throw "Cannot convert path to WSL format: $WindowsPath"
}

function Get-BashRuntime {
    if ($env:SHIYI_BASH -and (Test-Path -LiteralPath $env:SHIYI_BASH)) {
        return @{ Type = 'exe'; Path = (Resolve-Path -LiteralPath $env:SHIYI_BASH).Path; Source = 'SHIYI_BASH' }
    }

    $pathBash = Get-Command bash -ErrorAction SilentlyContinue
    if ($pathBash) {
        return @{ Type = 'exe'; Path = $pathBash.Source; Source = 'PATH bash' }
    }

    $gitBashCandidates = @(
        'C:\Program Files\Git\bin\bash.exe',
        'C:\Program Files\Git\usr\bin\bash.exe',
        'C:\Program Files (x86)\Git\bin\bash.exe'
    )

    foreach ($candidate in $gitBashCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            return @{ Type = 'exe'; Path = $candidate; Source = 'Git Bash' }
        }
    }

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCommand) {
        $gitDir = Split-Path -Parent $gitCommand.Source
        $searchRoots = @(
            $gitDir,
            (Split-Path -Parent $gitDir),
            (Split-Path -Parent (Split-Path -Parent $gitDir))
        ) | Where-Object { $_ } | Select-Object -Unique

        foreach ($root in $searchRoots) {
            foreach ($relativePath in @('bin\bash.exe', 'usr\bin\bash.exe')) {
                $candidate = Join-Path $root $relativePath
                if (Test-Path -LiteralPath $candidate) {
                    return @{ Type = 'exe'; Path = $candidate; Source = 'Git adjacent bash' }
                }
            }
        }
    }

    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($wsl) {
        $wslDistros = @(& $wsl.Source --list --quiet 2>$null)
        if ($LASTEXITCODE -eq 0 -and ($wslDistros | Where-Object { $_.Trim() })) {
            return @{ Type = 'wsl'; Path = $wsl.Source; Source = 'WSL' }
        }
    }

    return $null
}

$runtime = Get-BashRuntime
if (-not $runtime) {
    Write-Error 'No Bash runtime found. Install Git for Windows or WSL, or set SHIYI_BASH to your bash.exe path.'
    exit 1
}

if ($runtime.Type -eq 'exe') {
    $planned = @($runtime.Path, $scriptPath) + $ScriptArgs
    if ($DryRun) {
        Write-Output "Runtime: $($runtime.Source)"
        Write-Output ('Command: ' + ((($planned | ForEach-Object { '"' + $_ + '"' }) -join ' ')))
        exit 0
    }

    Push-Location $repoRoot
    try {
        & $runtime.Path $scriptPath @ScriptArgs
        if ($null -ne $LASTEXITCODE) {
            exit $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }

    exit 0
}

$wslRepoRoot = Convert-ToWslPath -WindowsPath $repoRoot
$wslScriptPath = Convert-ToWslPath -WindowsPath $scriptPath
$quotedBashArgs = ((@($wslScriptPath) + $ScriptArgs) | ForEach-Object { Quote-BashArg $_ })
$quotedCommand = 'cd ' + (Quote-BashArg $wslRepoRoot) + ' && bash ' + ($quotedBashArgs -join ' ')

if ($DryRun) {
    Write-Output "Runtime: $($runtime.Source)"
    Write-Output ('Command: wsl.exe bash -lc ' + $quotedCommand)
    exit 0
}

& $runtime.Path 'bash' '-lc' $quotedCommand
if ($null -ne $LASTEXITCODE) {
    exit $LASTEXITCODE
}

exit 0