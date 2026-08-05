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

function Assert-SameFileHash {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf) -or
        -not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        throw "Cannot compare missing install payload files: $Source -> $Destination"
    }
    $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    if ($sourceHash -ne $destinationHash) {
        throw "Installed payload differs from verified source: $Destination"
    }
}

function Get-RelativeFileList {
    param([Parameter(Mandatory = $true)][string]$Root)

    $normalizedRoot = Get-NormalizedPath $Root
    return @(
        Get-ChildItem -LiteralPath $normalizedRoot -File -Recurse -Force |
            ForEach-Object {
                $_.FullName.Substring($normalizedRoot.Length).TrimStart(
                    [char[]]@('\', '/')
                )
            } |
            Sort-Object
    )
}

function Assert-SameDirectoryTree {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $sourceFiles = @(Get-RelativeFileList -Root $Source)
    $destinationFiles = @(Get-RelativeFileList -Root $Destination)
    $difference = @(Compare-Object -ReferenceObject $sourceFiles -DifferenceObject $destinationFiles)
    if ($difference.Count -ne 0) {
        throw "Installed Agent tree has missing or extra files."
    }
    foreach ($relativePath in $sourceFiles) {
        Assert-SameFileHash `
            -Source (Join-Path $Source $relativePath) `
            -Destination (Join-Path $Destination $relativePath)
    }
}

$workspace = Get-NormalizedPath $WorkspaceRoot
$hostRoot = Get-NormalizedPath $HostInstallPath
$managedRoot = Get-NormalizedPath (Join-Path $env:LOCALAPPDATA "Auralith_Editer")
$finalTargetRoot = Get-NormalizedPath $InstallPath
$targetRoot = $finalTargetRoot
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
$agentRoot = Join-Path $workspace "desktop-sdk\ChromiumBasedEditors\plugins\ai-agent"
$agentBuildScript = Join-Path $agentRoot "scripts\build.js"
$agentRegistry = Join-Path $agentRoot "src\office-tools\office-capabilities.json"
$viteCommand = Join-Path $agentRoot "node_modules\.bin\vite.cmd"
$agentHostRuntimeJs = Join-Path $workspace "web-apps\apps\common\main\lib\auralith-agent-host-runtime.js"
$agentHostJs = Join-Path $workspace "web-apps\apps\common\main\lib\auralith-agent-host.js"
$agentHostCss = Join-Path $workspace "web-apps\apps\common\main\lib\auralith-agent-host.css"
$agentHostTokensCss = Join-Path $workspace "web-apps\apps\common\main\lib\auralith-agent-host-tokens.css"
$agentHostBaseLayoutCss = Join-Path $workspace "web-apps\apps\common\main\lib\auralith-agent-host-base-layout.css"
$agentHostWriteApprovalCss = Join-Path $workspace "web-apps\apps\common\main\lib\auralith-agent-host-write-approval.css"
$agentWriteProfilesJs = Join-Path $workspace "web-apps\apps\common\main\lib\auralith-agent-write-profiles.js"
$agentWriteExecutorJs = Join-Path $workspace "web-apps\apps\common\main\lib\auralith-agent-write-executor.js"
$agentWriteTransportJs = Join-Path $workspace "web-apps\apps\common\main\lib\auralith-agent-write-transport.js"
$sdkjsRoot = Join-Path $workspace "sdkjs"
$snapshotSource = Join-Path $sdkjsRoot "word\Editor\document\multimodal-snapshot.js"
$sdkGruntFile = Join-Path $sdkjsRoot "build\Gruntfile.js"
$sdkLicenseHeader = Join-Path $sdkjsRoot "build\license.header"
$sdkGruntCommand = Join-Path $sdkjsRoot "build\node_modules\.bin\grunt.cmd"
$sampleDocument = Join-Path $workspace "desktop-sdk\ChromiumBasedEditors\plugins\ai-agent\test-fixtures\docx-reader\known\04-inline-image-caption.docx"
$launcherSource = Join-Path $workspace "tools\AuralithTestLauncher.cs"

$requiredSourceFiles = @(
    $hostExecutable,
    $agentBuildScript,
    $agentRegistry,
    $viteCommand,
    $agentHostRuntimeJs,
    $agentHostJs,
    $agentHostCss,
    $agentHostTokensCss,
    $agentHostBaseLayoutCss,
    $agentHostWriteApprovalCss,
    $agentWriteProfilesJs,
    $agentWriteExecutorJs,
    $agentWriteTransportJs,
    $sdkGruntFile,
    $sdkLicenseHeader,
    $sdkGruntCommand,
    $snapshotSource,
    $sampleDocument,
    $launcherSource
)
foreach ($requiredFile in $requiredSourceFiles) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required source input is missing: $requiredFile"
    }
}

$nodeCommand = (Get-Command node -ErrorAction Stop).Source
$nodeMajorVersion = & $nodeCommand -p "Number(process.versions.node.split('.')[0])"
if ($LASTEXITCODE -ne 0 -or [int]$nodeMajorVersion -ne 20) {
    throw "Auralith Agent installation requires Node.js 20."
}
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    "auralith-editer-install-" + [Guid]::NewGuid().ToString("N")
)
$stagedRoot = Join-Path $managedRoot (
    ".install-stage-" + [Guid]::NewGuid().ToString("N")
)
$agentBundleBuild = Join-Path $temporaryRoot "agent"
$sdkjsIsolated = Join-Path $temporaryRoot "sdkjs"
$sdkBuild = Join-Path $sdkjsIsolated "deploy\sdkjs\word"
$sdkSourceJunctions = @()
$promoted = $false
$stagingOwned = $false
$installationResult = $null

try {
    New-Item -ItemType Directory -Path $agentBundleBuild -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $sdkjsIsolated "build") -Force | Out-Null

Push-Location $agentRoot
try {
    & $viteCommand build --outDir $agentBundleBuild --emptyOutDir
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build the Auralith Agent into temporary output."
    }
} finally {
    Pop-Location
}
$temporaryIndex = Join-Path $agentBundleBuild "index.html"
if (Test-Path -LiteralPath $temporaryIndex) {
    Remove-Item -LiteralPath $temporaryIndex -Force
}
$manifestBuilder = @'
import fs from "node:fs";
import { pathToFileURL } from "node:url";
const modulePath = process.argv[1];
const outputPath = process.argv[2];
const buildModule = await import(`${pathToFileURL(modulePath).href}?installer=${Date.now()}`);
const registry = buildModule.loadOfficeCapabilityRegistry();
const manifest = buildModule.createBuiltInAgentManifest(registry);
fs.writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);
'@
& $nodeCommand `
    --input-type=module `
    -e `
    $manifestBuilder `
    $agentBuildScript `
    (Join-Path $agentBundleBuild "manifest.json")
if ($LASTEXITCODE -ne 0) {
    throw "Failed to generate the Agent manifest from the canonical registry."
}

foreach ($sourceDirectory in @("configs", "common", "vendor", "word", "cell", "slide", "visio", "pdf")) {
    $sourcePath = Join-Path $sdkjsRoot $sourceDirectory
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        throw "Required SDKJS source directory is missing: $sourcePath"
    }
    $junctionPath = Join-Path $sdkjsIsolated $sourceDirectory
    New-Item `
        -ItemType Junction `
        -Path $junctionPath `
        -Target $sourcePath | Out-Null
    $sdkSourceJunctions += $junctionPath
}
Copy-Item -LiteralPath $sdkGruntFile -Destination (Join-Path $sdkjsIsolated "build\Gruntfile.js")
Copy-Item -LiteralPath $sdkLicenseHeader -Destination (Join-Path $sdkjsIsolated "build\license.header")
$nodeModulesJunction = Join-Path $sdkjsIsolated "build\node_modules"
New-Item `
    -ItemType Junction `
    -Path $nodeModulesJunction `
    -Target (Join-Path $sdkjsRoot "build\node_modules") | Out-Null
$sdkSourceJunctions += $nodeModulesJunction
$isolatedGruntCommand = Join-Path $sdkjsIsolated "build\node_modules\.bin\grunt.cmd"
Push-Location (Join-Path $sdkjsIsolated "build")
try {
    & $isolatedGruntCommand `
        compile-word `
        --desktop `
        --level=WHITESPACE_ONLY `
        --formatting=PRETTY_PRINT
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to compile the isolated desktop Word SDK bundle."
    }
} finally {
    Pop-Location
}

$requiredBuildFiles = @(
    (Join-Path $agentBundleBuild "manifest.json"),
    (Join-Path $agentBundleBuild "reader.html"),
    (Join-Path $agentBundleBuild "reader.js"),
    (Join-Path $agentBundleBuild "reader.css"),
    (Join-Path $sdkBuild "sdk-all-min.js"),
    (Join-Path $sdkBuild "sdk-all.js")
)
foreach ($requiredFile in $requiredBuildFiles) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required temporary build artifact is missing: $requiredFile"
    }
}
foreach ($hostJavaScript in @(
    $agentWriteProfilesJs,
    $agentHostRuntimeJs,
    $agentWriteExecutorJs,
    $agentWriteTransportJs,
    $agentHostJs
)) {
    & $nodeCommand --check $hostJavaScript
    if ($LASTEXITCODE -ne 0) {
        throw "Host JavaScript syntax validation failed: $hostJavaScript"
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
if (Test-Path -LiteralPath (Join-Path $agentBundleBuild "index.html")) {
    throw "The built-in Agent staging directory must not contain index.html."
}
$canonicalRegistry = Get-Content -LiteralPath $agentRegistry -Raw | ConvertFrom-Json
$builtAgentManifest = Get-Content -LiteralPath (Join-Path $agentBundleBuild "manifest.json") -Raw |
    ConvertFrom-Json
$expectedCapabilities = @(
    $canonicalRegistry.capabilities |
        Where-Object { $_.productionEnabled -eq $true } |
        ForEach-Object { $_.id }
)
$actualCapabilities = @($builtAgentManifest.capabilities)
if ($builtAgentManifest.name -ne "Auralith Agent" -or
    $builtAgentManifest.kind -ne "builtin-editor-surface" -or
    $builtAgentManifest.entry -ne "reader.html" -or
    $builtAgentManifest.protocolVersion -ne $canonicalRegistry.protocolVersion -or
    $builtAgentManifest.capabilityRegistryVersion -ne $canonicalRegistry.registryVersion -or
    @(Compare-Object -ReferenceObject $expectedCapabilities -DifferenceObject $actualCapabilities).Count -ne 0 -or
    @($builtAgentManifest.capabilityStatus).Count -ne @($canonicalRegistry.capabilities).Count) {
    throw "The temporary Agent manifest does not match the canonical capability registry."
}

if (Test-Path -LiteralPath $finalTargetRoot) {
    $runningFromTarget = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try {
            $_.Path -and (Get-NormalizedPath $_.Path).StartsWith(
                $finalTargetRoot + [System.IO.Path]::DirectorySeparatorChar,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        } catch {
            $false
        }
    }
    if ($runningFromTarget) {
        throw "Close the running Auralith_Editer test build before reinstalling."
    }
}

Assert-PathInside -Path $stagedRoot -Parent $managedRoot
Assert-NoReparsePoint -Path $stagedRoot -StopAt $managedRoot
if (Test-Path -LiteralPath $stagedRoot) {
    throw "Refusing to reuse an existing install staging directory: $stagedRoot"
}
$targetRoot = $stagedRoot
New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
$stagingOwned = $true
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

$hostRuntimeTarget = Join-Path $commonMain "lib\auralith-agent-host-runtime.js"
$hostScriptTarget = Join-Path $commonMain "lib\auralith-agent-host.js"
$hostStyleTarget = Join-Path $commonMain "lib\auralith-agent-host.css"
$hostTokensTarget = Join-Path $commonMain "lib\auralith-agent-host-tokens.css"
$hostBaseLayoutTarget = Join-Path $commonMain "lib\auralith-agent-host-base-layout.css"
$hostWriteApprovalTarget = Join-Path $commonMain "lib\auralith-agent-host-write-approval.css"
$writeProfilesTarget = Join-Path $commonMain "lib\auralith-agent-write-profiles.js"
$writeExecutorTarget = Join-Path $commonMain "lib\auralith-agent-write-executor.js"
$writeTransportTarget = Join-Path $commonMain "lib\auralith-agent-write-transport.js"
Copy-Item -LiteralPath $agentHostRuntimeJs -Destination $hostRuntimeTarget -Force
Copy-Item -LiteralPath $agentHostJs -Destination $hostScriptTarget -Force
Copy-Item -LiteralPath $agentHostCss -Destination $hostStyleTarget -Force
Copy-Item -LiteralPath $agentHostTokensCss -Destination $hostTokensTarget -Force
Copy-Item -LiteralPath $agentHostBaseLayoutCss -Destination $hostBaseLayoutTarget -Force
Copy-Item -LiteralPath $agentHostWriteApprovalCss -Destination $hostWriteApprovalTarget -Force
Copy-Item -LiteralPath $agentWriteProfilesJs -Destination $writeProfilesTarget -Force
Copy-Item -LiteralPath $agentWriteExecutorJs -Destination $writeExecutorTarget -Force
Copy-Item -LiteralPath $agentWriteTransportJs -Destination $writeTransportTarget -Force

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
        '\s*<script\b[^>]*src=["'']\.\./\.\./common/main/lib/auralith-agent-host-runtime\.js["''][^>]*>\s*</script>\s*',
        "`r`n",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    $html = [regex]::Replace(
        $html,
        '\s*<script\b[^>]*src=["'']\.\./\.\./common/main/lib/auralith-agent-write-profiles\.js["''][^>]*>\s*</script>\s*',
        "`r`n",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    $html = [regex]::Replace(
        $html,
        '\s*<script\b[^>]*src=["'']\.\./\.\./common/main/lib/auralith-agent-write-executor\.js["''][^>]*>\s*</script>\s*',
        "`r`n",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    $html = [regex]::Replace(
        $html,
        '\s*<script\b[^>]*src=["'']\.\./\.\./common/main/lib/auralith-agent-write-transport\.js["''][^>]*>\s*</script>\s*',
        "`r`n",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    $html = [regex]::Replace(
        $html,
        '\s*<script\b[^>]*src=["'']\.\./\.\./common/main/lib/auralith-agent-host\.js["''][^>]*>\s*</script>\s*',
        "`r`n",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    $writeProfilesInjection = if ($editorHost.Kind -eq "document") {
        @'
    <script src="../../common/main/lib/auralith-agent-write-profiles.js"></script>
'@
    } else {
        ""
    }
    $writeExecutorInjection = if ($editorHost.Kind -eq "document") {
        @'
    <script src="../../common/main/lib/auralith-agent-write-executor.js"></script>
    <script src="../../common/main/lib/auralith-agent-write-transport.js"></script>
'@
    } else {
        ""
    }
    $injection = @"
    $hostMarker
    <link rel="stylesheet" href="../../common/main/lib/auralith-agent-host.css">
$writeProfilesInjection
    <script src="../../common/main/lib/auralith-agent-host-runtime.js"></script>
$writeExecutorInjection
    <script src="../../common/main/lib/auralith-agent-host.js" data-auralith-editor="$($editorHost.Kind)"></script>
"@
    if (-not $html.Contains("</body>")) {
        throw "Cannot locate </body> in editor host page: $editorIndex"
    }
    $html = $html.Replace("</body>", "$injection`r`n</body>")
    if (
        ([regex]::Matches($html, [regex]::Escape("auralith-agent-host.css"))).Count -ne 1 -or
        ([regex]::Matches($html, [regex]::Escape("auralith-agent-host-runtime.js"))).Count -ne 1 -or
        ([regex]::Matches($html, [regex]::Escape("auralith-agent-host.js"))).Count -ne 1 -or
        ($editorHost.Kind -eq "document" -and
            ([regex]::Matches($html, [regex]::Escape("auralith-agent-write-profiles.js"))).Count -ne 1) -or
        ($editorHost.Kind -eq "document" -and
            ([regex]::Matches($html, [regex]::Escape("auralith-agent-write-executor.js"))).Count -ne 1) -or
        ($editorHost.Kind -eq "document" -and
            ([regex]::Matches($html, [regex]::Escape("auralith-agent-write-transport.js"))).Count -ne 1) -or
        ($editorHost.Kind -ne "document" -and
            (([regex]::Matches($html, [regex]::Escape("auralith-agent-write-profiles.js"))).Count -ne 0 -or
             ([regex]::Matches($html, [regex]::Escape("auralith-agent-write-executor.js"))).Count -ne 0 -or
             ([regex]::Matches($html, [regex]::Escape("auralith-agent-write-transport.js"))).Count -ne 0))
    ) {
        throw "Editor host injection is not idempotent: $editorIndex"
    }
    $runtimeIndex = $html.IndexOf("auralith-agent-host-runtime.js")
    $hostIndex = $html.IndexOf("auralith-agent-host.js")
    if ($editorHost.Kind -eq "document") {
        $profilesIndex = $html.IndexOf("auralith-agent-write-profiles.js")
        $executorIndex = $html.IndexOf("auralith-agent-write-executor.js")
        $transportIndex = $html.IndexOf("auralith-agent-write-transport.js")
        if (-not ($profilesIndex -lt $runtimeIndex -and
                  $runtimeIndex -lt $executorIndex -and
                  $executorIndex -lt $transportIndex -and
                  $transportIndex -lt $hostIndex)) {
            throw "Expected profiles < runtime < executor < transport < host: $editorIndex"
        }
    } elseif (-not ($runtimeIndex -lt $hostIndex)) {
        throw "Expected runtime < host: $editorIndex"
    }
    Set-Content -LiteralPath $editorIndex -Value $html -Encoding utf8
}

Assert-SameDirectoryTree -Source $agentBundleBuild -Destination $agentBundleTarget
foreach ($payloadPair in @(
    @($agentHostRuntimeJs, $hostRuntimeTarget),
    @($agentHostJs, $hostScriptTarget),
    @($agentHostCss, $hostStyleTarget),
    @($agentHostTokensCss, $hostTokensTarget),
    @($agentHostBaseLayoutCss, $hostBaseLayoutTarget),
    @($agentHostWriteApprovalCss, $hostWriteApprovalTarget),
    @($agentWriteProfilesJs, $writeProfilesTarget),
    @($agentWriteExecutorJs, $writeExecutorTarget),
    @($agentWriteTransportJs, $writeTransportTarget),
    @((Join-Path $sdkBuild "sdk-all-min.js"), (Join-Path $wordRuntime "sdk-all-min.js")),
    @((Join-Path $sdkBuild "sdk-all.js"), (Join-Path $wordRuntime "sdk-all.js"))
)) {
    Assert-SameFileHash -Source $payloadPair[0] -Destination $payloadPair[1]
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
        path = (Join-Path $finalTargetRoot "editors\web-apps\apps\common\main\auralith-agent")
        entry = "reader.html"
        registeredAsPlugin = $false
        currentCapabilities = $actualCapabilities
        capabilityRegistryVersion = $builtAgentManifest.capabilityRegistryVersion
        hostEditors = $editorHosts.Kind
    }
    sdkMinSha256 = (Get-FileHash -LiteralPath (Join-Path $wordRuntime "sdk-all-min.js") -Algorithm SHA256).Hash
    sdkAllSha256 = (Get-FileHash -LiteralPath (Join-Path $wordRuntime "sdk-all.js") -Algorithm SHA256).Hash
    payloadSha256 = [ordered]@{
        agentManifest = (Get-FileHash -LiteralPath (Join-Path $agentBundleTarget "manifest.json") -Algorithm SHA256).Hash
        hostRuntime = (Get-FileHash -LiteralPath $hostRuntimeTarget -Algorithm SHA256).Hash
        host = (Get-FileHash -LiteralPath $hostScriptTarget -Algorithm SHA256).Hash
        hostCss = (Get-FileHash -LiteralPath $hostStyleTarget -Algorithm SHA256).Hash
        hostTokensCss = (Get-FileHash -LiteralPath $hostTokensTarget -Algorithm SHA256).Hash
        hostBaseLayoutCss = (Get-FileHash -LiteralPath $hostBaseLayoutTarget -Algorithm SHA256).Hash
        hostWriteApprovalCss = (Get-FileHash -LiteralPath $hostWriteApprovalTarget -Algorithm SHA256).Hash
        writeProfiles = (Get-FileHash -LiteralPath $writeProfilesTarget -Algorithm SHA256).Hash
        writeExecutor = (Get-FileHash -LiteralPath $writeExecutorTarget -Algorithm SHA256).Hash
        writeTransport = (Get-FileHash -LiteralPath $writeTransportTarget -Algorithm SHA256).Hash
    }
    sampleDocument = $sampleDocument
}
$manifest |
    ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $targetRoot "Auralith_Editer-TestBuild.json") -Encoding utf8

$rollbackPath = $null
$oldInstallMoved = $false
$stageMovedToFinal = $false
$finalParent = Split-Path $finalTargetRoot -Parent
Assert-PathInside -Path $finalParent -Parent $managedRoot
if (-not (Test-Path -LiteralPath $finalParent -PathType Container)) {
    New-Item -ItemType Directory -Path $finalParent -Force | Out-Null
}

try {
    if (Test-Path -LiteralPath $finalTargetRoot) {
        if (-not (Test-Path -LiteralPath $finalTargetRoot -PathType Container)) {
            throw "The existing Auralith_Editer test install is not a directory: $finalTargetRoot"
        }
        $runningFromTarget = Get-Process -ErrorAction SilentlyContinue | Where-Object {
            try {
                $_.Path -and (Get-NormalizedPath $_.Path).StartsWith(
                    $finalTargetRoot + [System.IO.Path]::DirectorySeparatorChar,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            } catch {
                $false
            }
        }
        if ($runningFromTarget) {
            throw "Close the running Auralith_Editer test build before reinstalling."
        }

        $rollbackName = (
            ".install-backup-" +
            [System.IO.Path]::GetFileName($finalTargetRoot) + "-" +
            (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss") + "-" +
            [Guid]::NewGuid().ToString("N").Substring(0, 8)
        )
        $rollbackPath = Join-Path $managedRoot $rollbackName
        Assert-PathInside -Path $rollbackPath -Parent $managedRoot
        if (Test-Path -LiteralPath $rollbackPath) {
            throw "Refusing to reuse an existing install backup path: $rollbackPath"
        }

        # Re-check immediately before moving the existing installation. The
        # rename is recoverable and does not recursively delete user data.
        Assert-PathInside -Path $finalTargetRoot -Parent $managedRoot
        Assert-NoReparsePoint -Path $finalTargetRoot -StopAt $managedRoot
        Assert-NoReparsePoint -Path $rollbackPath -StopAt $managedRoot
        [System.IO.Directory]::Move($finalTargetRoot, $rollbackPath)
        $oldInstallMoved = $true
    }

    Assert-PathInside -Path $stagedRoot -Parent $managedRoot
    Assert-NoReparsePoint -Path $stagedRoot -StopAt $managedRoot
    Assert-NoReparsePoint -Path $finalParent -StopAt $managedRoot
    Assert-NoReparsePoint -Path $finalTargetRoot -StopAt $managedRoot
    if (Test-Path -LiteralPath $finalTargetRoot) {
        throw "The final install path changed during promotion: $finalTargetRoot"
    }
    [System.IO.Directory]::Move($stagedRoot, $finalTargetRoot)
    $stagingOwned = $false
    $stageMovedToFinal = $true

    $finalCommonMain = Join-Path $finalTargetRoot "editors\web-apps\apps\common\main"
    $finalAgentBundleTarget = Join-Path $finalCommonMain "auralith-agent"
    $finalWordRuntime = Join-Path $finalTargetRoot "editors\sdkjs\word"
    Assert-SameDirectoryTree -Source $agentBundleBuild -Destination $finalAgentBundleTarget
    foreach ($payloadPair in @(
        @($agentHostRuntimeJs, (Join-Path $finalCommonMain "lib\auralith-agent-host-runtime.js")),
        @($agentHostJs, (Join-Path $finalCommonMain "lib\auralith-agent-host.js")),
        @($agentHostCss, (Join-Path $finalCommonMain "lib\auralith-agent-host.css")),
        @($agentHostTokensCss, (Join-Path $finalCommonMain "lib\auralith-agent-host-tokens.css")),
        @($agentHostBaseLayoutCss, (Join-Path $finalCommonMain "lib\auralith-agent-host-base-layout.css")),
        @($agentHostWriteApprovalCss, (Join-Path $finalCommonMain "lib\auralith-agent-host-write-approval.css")),
        @($agentWriteProfilesJs, (Join-Path $finalCommonMain "lib\auralith-agent-write-profiles.js")),
        @($agentWriteExecutorJs, (Join-Path $finalCommonMain "lib\auralith-agent-write-executor.js")),
        @($agentWriteTransportJs, (Join-Path $finalCommonMain "lib\auralith-agent-write-transport.js")),
        @((Join-Path $sdkBuild "sdk-all-min.js"), (Join-Path $finalWordRuntime "sdk-all-min.js")),
        @((Join-Path $sdkBuild "sdk-all.js"), (Join-Path $finalWordRuntime "sdk-all.js"))
    )) {
        Assert-SameFileHash -Source $payloadPair[0] -Destination $payloadPair[1]
    }
    $promoted = $true
} catch {
    $promotionError = $_
    $recoveryErrors = @()
    if ($stageMovedToFinal -and (Test-Path -LiteralPath $finalTargetRoot)) {
        try {
            Assert-PathInside -Path $finalTargetRoot -Parent $managedRoot
            Assert-NoReparsePoint -Path $finalTargetRoot -StopAt $managedRoot
            Assert-NoReparsePoint -Path $stagedRoot -StopAt $managedRoot
            if (Test-Path -LiteralPath $stagedRoot) {
                throw "Cannot quarantine the failed promoted install because staging was recreated: $stagedRoot"
            }
            [System.IO.Directory]::Move($finalTargetRoot, $stagedRoot)
            $stagingOwned = $true
            $stageMovedToFinal = $false
        } catch {
            $recoveryErrors += "Failed to quarantine the new install: $($_.Exception.Message)"
        }
    }
    if ($oldInstallMoved) {
        if (Test-Path -LiteralPath $finalTargetRoot) {
            $recoveryErrors += (
                "The previous install remains recoverable at $rollbackPath because " +
                "the final path is occupied: $finalTargetRoot"
            )
        } else {
            try {
                Assert-PathInside -Path $rollbackPath -Parent $managedRoot
                Assert-NoReparsePoint -Path $rollbackPath -StopAt $managedRoot
                Assert-NoReparsePoint -Path $finalParent -StopAt $managedRoot
                Assert-NoReparsePoint -Path $finalTargetRoot -StopAt $managedRoot
                [System.IO.Directory]::Move($rollbackPath, $finalTargetRoot)
                $oldInstallMoved = $false
                $rollbackPath = $null
            } catch {
                $recoveryErrors += (
                    "Failed to restore the previous install from $rollbackPath`: " +
                    $_.Exception.Message
                )
            }
        }
    }
    if ($recoveryErrors.Count -ne 0) {
        throw (
            "Install promotion failed: " + $promotionError.Exception.Message +
            " Recovery was incomplete. " + ($recoveryErrors -join " ")
        )
    }
    throw $promotionError
}

$shortcutPath = $null
if (-not $SkipShortcut) {
    try {
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $shortcutPath = Join-Path $desktopPath "Auralith_Editer Test.lnk"
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = Join-Path $finalTargetRoot "Auralith_Editer.Launcher.exe"
        $shortcut.WorkingDirectory = $finalTargetRoot
        $shortcut.Arguments = "`"$sampleDocument`""
        $shortcut.IconLocation = (Join-Path $finalTargetRoot "app.ico")
        $shortcut.Description = "Auralith_Editer built-in Agent test build"
        $shortcut.Save()
    } catch {
        Write-Warning "The test build was installed, but the desktop shortcut could not be created: $_"
        $shortcutPath = $null
    }
}

$installationResult = [pscustomobject]@{
    InstallPath = $finalTargetRoot
    Executable = (Join-Path $finalTargetRoot "Auralith_Editer.exe")
    AgentPath = (Join-Path $finalTargetRoot "editors\web-apps\apps\common\main\auralith-agent")
    RegisteredAsPlugin = $false
    SampleDocument = $sampleDocument
    Shortcut = $shortcutPath
    PreviousInstallBackup = $rollbackPath
}
} finally {
    $temporaryCleanupSafe = $true
    foreach ($junctionPath in $sdkSourceJunctions) {
        try {
            if (-not (Test-Path -LiteralPath $junctionPath)) {
                continue
            }
            $junctionItem = Get-Item -LiteralPath $junctionPath -Force
            if (($junctionItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                $temporaryCleanupSafe = $false
                Write-Warning "Refusing to clean a temporary SDK tree containing a non-junction path: $junctionPath"
                continue
            }
            $junctionItem.Delete()
        } catch {
            $temporaryCleanupSafe = $false
            Write-Warning "Could not safely remove temporary SDK junction $junctionPath`: $_"
        }
    }
    if ($temporaryCleanupSafe -and (Test-Path -LiteralPath $temporaryRoot)) {
        try {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        } catch {
            Write-Warning "Could not remove the temporary build directory $temporaryRoot`: $_"
        }
    }
    if (-not $promoted -and $stagingOwned -and (Test-Path -LiteralPath $stagedRoot)) {
        try {
            Assert-PathInside -Path $stagedRoot -Parent $managedRoot
            Assert-NoReparsePoint -Path $stagedRoot -StopAt $managedRoot
            Remove-Item -LiteralPath $stagedRoot -Recurse -Force
        } catch {
            Write-Warning "Could not safely remove failed install staging directory $stagedRoot`: $_"
        }
    }
}

$installationResult
