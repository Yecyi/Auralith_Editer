[CmdletBinding()]
param(
    [string]$HostInstallPath = "C:\Program Files\ONLYOFFICE\DesktopEditors",
    [string]$InstallPath = (Join-Path $env:LOCALAPPDATA "Auralith_Editer\TestBuild"),
    [string]$WorkspaceRoot = "",
    [switch]$SkipShortcut
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Split-Path $PSScriptRoot -Parent
}

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

function Test-PathsOverlap {
    param(
        [Parameter(Mandatory = $true)][string]$First,
        [Parameter(Mandatory = $true)][string]$Second
    )

    $normalizedFirst = Get-NormalizedPath $First
    $normalizedSecond = Get-NormalizedPath $Second
    $separator = [System.IO.Path]::DirectorySeparatorChar
    return (
        $normalizedFirst.Equals(
            $normalizedSecond,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -or
        $normalizedFirst.StartsWith(
            $normalizedSecond + $separator,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -or
        $normalizedSecond.StartsWith(
            $normalizedFirst + $separator,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    )
}

function Assert-NoReparsePoint {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$StopAt
    )

    $current = Get-NormalizedPath $Path
    $stop = Get-NormalizedPath $StopAt
    while ($current.StartsWith(
        $stop,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to modify a managed path through a reparse point: $current"
            }
        }
        if ($current.Equals($stop, [System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $parent = Split-Path $current -Parent
        if (-not $parent -or $parent -eq $current) {
            break
        }
        $current = $parent
    }
}

$workspace = Get-NormalizedPath $WorkspaceRoot
$hostRoot = Get-NormalizedPath $HostInstallPath
$managedRoot = Get-NormalizedPath (Join-Path $env:LOCALAPPDATA "Auralith_Editer")
$targetRoot = Get-NormalizedPath $InstallPath
Assert-PathInside -Path $targetRoot -Parent $managedRoot
if ($targetRoot.Equals($managedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "InstallPath must be a dedicated child directory, not the managed Auralith_Editer root."
}
if ((Test-PathsOverlap -First $targetRoot -Second $hostRoot) -or
    (Test-PathsOverlap -First $targetRoot -Second $workspace)) {
    throw "InstallPath must not overlap the host installation or source workspace."
}
Assert-NoReparsePoint -Path $targetRoot -StopAt $managedRoot

$hostExecutable = Join-Path $hostRoot "DesktopEditors.exe"
$legacyAgentPluginGuid = "{9DC93CDB-B576-4F0C-B55E-FCC9C48DD777}"
$legacyReaderPluginGuid = "{FD767ACC-663E-476F-8F5F-6AEB513DF6E6}"
$agentBundleBuild = Join-Path $workspace "desktop-sdk\ChromiumBasedEditors\plugins\ai-agent\deploy\auralith-agent"
$agentHostJs = Join-Path $workspace "web-apps\apps\common\main\lib\auralith-agent-host.js"
$agentHostCss = Join-Path $workspace "web-apps\apps\common\main\lib\auralith-agent-host.css"
$sdkBuild = Join-Path $workspace "sdkjs\deploy\sdkjs\word"
$snapshotSource = Join-Path $workspace "sdkjs\word\Editor\document\multimodal-snapshot.js"
$sampleDocument = Join-Path $workspace "desktop-sdk\ChromiumBasedEditors\plugins\ai-agent\test-fixtures\docx-reader\known\04-inline-image-caption.docx"
$launcherSource = Join-Path $workspace "tools\AuralithTestLauncher.cs"

$requiredFiles = @(
    $hostExecutable,
    (Join-Path $agentBundleBuild "manifest.json"),
    (Join-Path $agentBundleBuild "reader.html"),
    (Join-Path $agentBundleBuild "reader.js"),
    (Join-Path $agentBundleBuild "reader.css"),
    $agentHostJs,
    $agentHostCss,
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

$agentEntryHtml = Get-Content -LiteralPath (Join-Path $agentBundleBuild "reader.html") -Raw
$agentEntryReferences = [regex]::Matches(
    $agentEntryHtml,
    '(?:src|href)="\./([^"?]+)'
)
foreach ($referenceMatch in $agentEntryReferences) {
    $referencedFile = Join-Path $agentBundleBuild $referenceMatch.Groups[1].Value
    if (-not (Test-Path -LiteralPath $referencedFile -PathType Leaf)) {
        throw "Auralith Agent bundle dependency is missing: $referencedFile"
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

$pluginsRoot = Join-Path $targetRoot "editors\sdkjs-plugins"
foreach ($legacyGuid in @($legacyAgentPluginGuid, $legacyReaderPluginGuid)) {
    $legacyTarget = Join-Path $pluginsRoot $legacyGuid
    Assert-PathInside -Path $legacyTarget -Parent $targetRoot
    if (Test-Path -LiteralPath $legacyTarget) {
        Remove-Item -LiteralPath $legacyTarget -Recurse -Force
    }
}

$webAppsRoot = Join-Path $targetRoot "editors\web-apps"
$commonMain = Join-Path $webAppsRoot "apps\common\main"
$agentBundleTarget = Join-Path $commonMain "auralith-agent"
Assert-PathInside -Path $agentBundleTarget -Parent $targetRoot
if (Test-Path -LiteralPath $agentBundleTarget) {
    Remove-Item -LiteralPath $agentBundleTarget -Recurse -Force
}
New-Item -ItemType Directory -Path $agentBundleTarget -Force | Out-Null
Get-ChildItem -LiteralPath $agentBundleBuild -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $agentBundleTarget -Recurse -Force
}

$hostScriptTarget = Join-Path $commonMain "lib\auralith-agent-host.js"
$hostStyleTarget = Join-Path $commonMain "lib\auralith-agent-host.css"
Copy-Item -LiteralPath $agentHostJs -Destination $hostScriptTarget -Force
Copy-Item -LiteralPath $agentHostCss -Destination $hostStyleTarget -Force

$editorHosts = @(
    [pscustomobject]@{ Directory = "documenteditor"; Kind = "document" },
    [pscustomobject]@{ Directory = "spreadsheeteditor"; Kind = "spreadsheet" },
    [pscustomobject]@{ Directory = "presentationeditor"; Kind = "presentation" },
    [pscustomobject]@{ Directory = "pdfeditor"; Kind = "pdf" },
    [pscustomobject]@{ Directory = "visioeditor"; Kind = "visio" }
)

$hostMarker = "<!-- Auralith Agent built-in host -->"
foreach ($editorHost in $editorHosts) {
    $editorIndex = Join-Path $webAppsRoot "apps\$($editorHost.Directory)\main\index.html"
    if (-not (Test-Path -LiteralPath $editorIndex -PathType Leaf)) {
        throw "Editor host page is missing: $editorIndex"
    }

    $html = Get-Content -LiteralPath $editorIndex -Raw
    $html = [regex]::Replace(
        $html,
        '\s*<!-- Auralith Agent built-in host -->\s*',
        "`r`n"
    )
    $html = [regex]::Replace(
        $html,
        '\s*<link\b[^>]*href=["'']\.\./\.\./common/main/lib/auralith-agent-host\.css["''][^>]*>\s*',
        "`r`n",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    $html = [regex]::Replace(
        $html,
        '\s*<script\b[^>]*src=["'']\.\./\.\./common/main/lib/auralith-agent-host\.js["''][^>]*>\s*</script>\s*',
        "`r`n",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    $injection = @"
    $hostMarker
    <link rel="stylesheet" href="../../common/main/lib/auralith-agent-host.css">
    <script src="../../common/main/lib/auralith-agent-host.js" data-auralith-editor="$($editorHost.Kind)"></script>
"@
    if (-not $html.Contains("</body>")) {
        throw "Cannot locate </body> in editor host page: $editorIndex"
    }
    $html = $html.Replace("</body>", "$injection`r`n</body>")
    if (
        ([regex]::Matches($html, [regex]::Escape("auralith-agent-host.css"))).Count -ne 1 -or
        ([regex]::Matches($html, [regex]::Escape("auralith-agent-host.js"))).Count -ne 1
    ) {
        throw "Editor host injection is not idempotent: $editorIndex"
    }
    Set-Content -LiteralPath $editorIndex -Value $html -Encoding utf8
}

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
    agent = [ordered]@{
        name = "Auralith Agent"
        kind = "builtin-editor-surface"
        path = $agentBundleTarget
        entry = "reader.html"
        registeredAsPlugin = $false
        currentCapabilities = @("docx-multimodal-reader")
        hostEditors = $editorHosts.Kind
    }
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
    $shortcut.Description = "Auralith_Editer built-in Agent test build"
    $shortcut.Save()
}

[pscustomobject]@{
    InstallPath = $targetRoot
    Executable = $auralithExecutable
    AgentPath = $agentBundleTarget
    RegisteredAsPlugin = $false
    SampleDocument = $sampleDocument
    Shortcut = $shortcutPath
}
