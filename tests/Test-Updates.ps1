$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'ResizerUpdates.ps1')
function Assert($Condition,$Message) { if (-not $Condition) { throw $Message } }
$meta = Get-Content (Join-Path $root 'AppInfo.json') -Raw | ConvertFrom-Json
$current = [version]$meta.version
$newVersion = '{0}.{1}.0' -f $current.Major,($current.Minor+1)
$release = [pscustomobject]@{ tag_name=('v'+$newVersion); draft=$false; prerelease=$false; html_url=('https://github.com/'+$meta.repository+'/releases/tag/v'+$newVersion); assets=@([pscustomobject]@{name='ResizerJPG_portable.zip';browser_download_url=('https://github.com/'+$meta.repository+'/releases/download/v'+$newVersion+'/ResizerJPG_portable.zip');size=100;digest=('sha256:' + ('a'*64))}) }
$candidate = Get-ResizerRelease -Metadata $meta -Release $release
Assert ($candidate.Available -and $candidate.Version -eq $newVersion) 'New version must be detected.'
$release.tag_name = 'v'+$meta.version
Assert (-not (Get-ResizerRelease -Metadata $meta -Release $release).Available) 'Current version must not trigger update.'
$release.tag_name = 'v0.0.0'
Assert (-not (Get-ResizerRelease -Metadata $meta -Release $release).Available) 'Older version must not trigger downgrade.'
$release.tag_name = 'v'+$newVersion
$release.assets[0].browser_download_url = 'https://evil.example/package.zip'
$rejected = $false
try { Get-ResizerRelease -Metadata $meta -Release $release | Out-Null } catch { $rejected = $true }
Assert $rejected 'Untrusted asset URL must be rejected.'
Write-Host 'PASS: release comparison and asset source validation.'

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('resizer-update-test-' + [guid]::NewGuid())
$stage = Join-Path $fixture 'stage'
$app = Join-Path $fixture 'app'
[void](New-Item -ItemType Directory -Path $stage,$app)
try {
    Copy-Item -Path (Join-Path $root 'ResizerJPG_portable\*') -Destination $stage -Recurse
    Copy-Item -Path (Join-Path $root 'ResizerJPG_portable\*') -Destination $app -Recurse
    [IO.File]::WriteAllText((Join-Path $app 'my-product.jpg'),'original sentinel')
    $valid = Test-ResizerPackage -Directory $stage -ExpectedVersion $meta.version
    Assert ($valid.Files.Count -gt 5) 'Complete package must be verified.'
    [IO.File]::AppendAllText((Join-Path $stage 'ResizerUI.ps1'),'# corruption')
    $rejected = $false
    try { Test-ResizerPackage -Directory $stage -ExpectedVersion $meta.version | Out-Null } catch { $rejected = $true }
    Assert $rejected 'Modified package file must be rejected.'
    Copy-Item -LiteralPath (Join-Path $root 'ResizerJPG_portable\ResizerUI.ps1') -Destination $stage -Force
    $zip = Join-Path $fixture 'bad.zip'
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Create)
    [void]$archive.CreateEntry('../escape.ps1')
    $archive.Dispose()
    $rejected = $false
    try { Expand-ResizerPackage -ArchivePath $zip -Destination (Join-Path $fixture 'bad-stage') | Out-Null } catch { $rejected = $true }
    Assert $rejected 'ZIP traversal must be rejected.'
    & powershell.exe -NoProfile -File (Join-Path $root 'Install-Update.ps1') -AppDirectory $app -StageDirectory $stage -ExpectedVersion $meta.version -NoRestart
    Assert ($LASTEXITCODE -eq 0) 'Installer must succeed.'
    Assert ((Get-Content (Join-Path $app 'my-product.jpg') -Raw) -eq 'original sentinel') 'Installer must preserve user photos.'
    Assert (Test-Path (Join-Path $app '_updates')) 'Installer must keep a backup.'
    Assert ((Get-Content (Join-Path $app '_updates\status.json') -Raw | ConvertFrom-Json).status -eq 'installed') 'Installer must record success.'
    $futureVersion = '{0}.{1}.{2}' -f $current.Major,$current.Minor,($current.Build+1)
    $futureMeta = Get-Content (Join-Path $stage 'AppInfo.json') -Raw | ConvertFrom-Json
    $futureMeta.version = $futureVersion
    [IO.File]::WriteAllText((Join-Path $stage 'AppInfo.json'),($futureMeta | ConvertTo-Json))
    $manifest = Get-Content (Join-Path $stage 'package-manifest.json') -Raw | ConvertFrom-Json
    $manifest.version = $futureVersion
    $manifest.files.'AppInfo.json' = (Get-FileHash (Join-Path $stage 'AppInfo.json')).Hash
    [IO.File]::WriteAllText((Join-Path $stage 'package-manifest.json'),($manifest | ConvertTo-Json -Depth 4))
    $locked = [IO.File]::Open((Join-Path $app 'ResizerUI.ps1'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $arguments = '-NoProfile -File "{0}" -AppDirectory "{1}" -StageDirectory "{2}" -ExpectedVersion "{3}" -NoRestart' -f (Join-Path $root 'Install-Update.ps1'),$app,$stage,$futureVersion
        $process = Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList $arguments -RedirectStandardError (Join-Path $fixture 'expected-error.txt') -RedirectStandardOutput (Join-Path $fixture 'expected-output.txt') -Wait -PassThru
        Assert ($process.ExitCode -ne 0) 'Locked destination must trigger install failure.'
    } finally { $locked.Dispose() }
    Assert ((Get-Content (Join-Path $app 'AppInfo.json') -Raw | ConvertFrom-Json).version -eq $meta.version) 'Failed update must restore earlier metadata.'
    Assert ((Get-Content (Join-Path $app '_updates\status.json') -Raw | ConvertFrom-Json).status -eq 'failed') 'Rollback must be recorded.'
    Write-Host 'PASS: manifest hashes, ZIP traversal protection, installer, backup, rollback after copy failure, preservation of user file.'
} finally {
    $full = [IO.Path]::GetFullPath($fixture)
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\resizer-update-test-'
    if ($full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $full -Recurse -Force }
}
