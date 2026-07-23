[CmdletBinding()]
param(
    [string]$HostInstallPath = "C:\Program Files\ONLYOFFICE\DesktopEditors",
    [string]$InstallPath = (Join-Path $env:LOCALAPPDATA "Auralith_Editer\TestBuild"),
    [string]$WorkspaceRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$SkipShortcut
)

$ErrorActionPreference = "Stop"

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
}

function Assert-PathInside {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Parent
    )

    $normalizedPath = Get-NormalizedPath $Path
    $normalizedParent = Get-NormalizedPath $Parent
    $parentPrefix = $normalizedParent + [System.IO.Path]::DirectorySeparatorChar
    if (
        $normalizedPath -ne $normalizedParent -and
        -not $normalizedPath.StartsWith(
            $parentPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw "Refusing to modify a path outside the managed Auralith_Editer directory: $normalizedPath"
    }
}

$workspace = Get-NormalizedPath $WorkspaceRoot
$hostRoot = Get-NormalizedPath $HostInstallPath
$managedRoot = Get-NormalizedPath (Join-Path $env:LOCALAPPDATA "Auralith_Editer")
$targetRoot = Get-NormalizedPath $InstallPath
Assert-PathInside -Path $targetRoot -Parent $managedRoot

$hostExecutable = Join-Path $hostRoot "DesktopEditors.exe"
$pluginBuild = Join-Path $workspace "desktop-sdk\ChromiumBasedEditors\plugins\ai-agent\deploy\{9DC93CDB-B576-4F0C-B55E-FCC9C48DD777}"
$sdkBuild = Join-Path $workspace "sdkjs\deploy\sdkjs\word"
$snapshotSource = Join-Path $workspace "sdkjs\word\Editor\document\multimodal-snapshot.js"
$sampleDocument = Join-Path $workspace "desktop-sdk\ChromiumBasedEditors\plugins\ai-agent\test-fixtures\docx-reader\known\04-inline-image-caption.docx"
$launcherSource = Join-Path $workspace "tools\AuralithTestLauncher.cs"

$requiredFiles = @(
    $hostExecutable,
    (Join-Path $pluginBuild "config.json"),
    (Join-Path $pluginBuild "reader.html"),
    (Join-Path $pluginBuild "reader.js"),
    (Join-Path $sdkBuild "sdk-all-min.js"),
    (Join-Path $sdkBuild "sdk-all.js"),
    $snapshotSource,
    $sampleDocument,
    $launcherSource
)
foreach ($requiredFile in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required build artifact is missing: $requiredFile"
    }
}

if (Test-Path -LiteralPath $targetRoot) {
    $runningFromTarget = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try {
            $_.Path -and (Get-NormalizedPath $_.Path).StartsWith(
                $targetRoot + [System.IO.Path]::DirectorySeparatorChar,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        } catch {
            $false
        }
    }
    if ($runningFromTarget) {
        throw "Close the running Auralith_Editer test build before reinstalling."
    }

    Assert-PathInside -Path $targetRoot -Parent $managedRoot
    Remove-Item -LiteralPath $targetRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
Get-ChildItem -LiteralPath $hostRoot -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $targetRoot -Recurse -Force
}

$wordRuntime = Join-Path $targetRoot "editors\sdkjs\word"
Copy-Item -LiteralPath (Join-Path $sdkBuild "sdk-all-min.js") -Destination (Join-Path $wordRuntime "sdk-all-min.js") -Force
Copy-Item -LiteralPath (Join-Path $sdkBuild "sdk-all.js") -Destination (Join-Path $wordRuntime "sdk-all.js") -Force

$pluginTarget = Join-Path $targetRoot "editors\sdkjs-plugins\{9DC93CDB-B576-4F0C-B55E-FCC9C48DD777}"
Assert-PathInside -Path $pluginTarget -Parent $targetRoot
if (Test-Path -LiteralPath $pluginTarget) {
    Remove-Item -LiteralPath $pluginTarget -Recurse -Force
}
New-Item -ItemType Directory -Path $pluginTarget -Force | Out-Null
Get-ChildItem -LiteralPath $pluginBuild -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $pluginTarget -Recurse -Force
}

$installedConfigPath = Join-Path $pluginTarget "config.json"
$installedConfig = Get-Content -LiteralPath $installedConfigPath -Raw | ConvertFrom-Json
$installedConfig | Add-Member -NotePropertyName "version" -NotePropertyValue "99.999.999" -Force
$installedConfig |
    ConvertTo-Json -Depth 32 |
    Set-Content -LiteralPath $installedConfigPath -Encoding utf8

$auralithExecutable = Join-Path $targetRoot "Auralith_Editer.exe"
Copy-Item -LiteralPath $hostExecutable -Destination $auralithExecutable -Force
$launcherTarget = Join-Path $targetRoot "Auralith_Editer.Launcher.exe"
$compilerCandidates = @(
    (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$csharpCompiler = $compilerCandidates |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if (-not $csharpCompiler) {
    throw "The Windows .NET C# compiler required for the Auralith_Editer launcher is missing."
}

& $csharpCompiler `
    /nologo `
    /target:winexe `
    /optimize+ `
    "/out:$launcherTarget" `
    $launcherSource
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $launcherTarget)) {
    throw "Failed to build the Auralith_Editer test launcher."
}

$manifest = [ordered]@{
    product = "Auralith_Editer"
    installedAt = (Get-Date).ToUniversalTime().ToString("o")
    workspace = $workspace
    pluginGuid = "{9DC93CDB-B576-4F0C-B55E-FCC9C48DD777}"
    pluginVersion = "99.999.999"
    sdkMinSha256 = (Get-FileHash -LiteralPath (Join-Path $wordRuntime "sdk-all-min.js") -Algorithm SHA256).Hash
    sdkAllSha256 = (Get-FileHash -LiteralPath (Join-Path $wordRuntime "sdk-all.js") -Algorithm SHA256).Hash
    sampleDocument = $sampleDocument
}
$manifest |
    ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $targetRoot "Auralith_Editer-TestBuild.json") -Encoding utf8

$shortcutPath = $null
if (-not $SkipShortcut) {
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktopPath "Auralith_Editer Test.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $launcherTarget
    $shortcut.WorkingDirectory = $targetRoot
    $shortcut.Arguments = "`"$sampleDocument`""
    $shortcut.IconLocation = (Join-Path $targetRoot "app.ico")
    $shortcut.Description = "Auralith_Editer DOCX multimodal reader test build"
    $shortcut.Save()
}

[pscustomobject]@{
    InstallPath = $targetRoot
    Executable = $auralithExecutable
    PluginPath = $pluginTarget
    SampleDocument = $sampleDocument
    Shortcut = $shortcutPath
}
