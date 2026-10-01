function Get-ResizerAppInfo {
    param([string]$Directory = $PSScriptRoot)
    return Get-Content -LiteralPath (Join-Path $Directory 'AppInfo.json') -Raw | ConvertFrom-Json
}

function Get-ResizerManagedFiles {
    return @('AppInfo.json','ResizerJPG.ps1','ResizerUI.ps1','ResizerWindow.xaml','ResizerUpdates.ps1','Install-Update.ps1','digital-xperts-logo.png','lucide-paths.json','resizer-jpg.ico','README.md','LICENSE','THIRD-PARTY-NOTICES.txt','Uruchom Resizer JPG.vbs','Utworz skrot z ikona.vbs','UtworzSkrotZIkona.ps1')
}

function Get-ResizerRelease {
    param($Metadata, $Release)
    if ($Metadata.repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Niepoprawny adres repozytorium GitHub.' }
    if ($null -eq $Release) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        try {
            $Release = Invoke-RestMethod -Uri ('https://api.github.com/repos/{0}/releases/latest' -f $Metadata.repository) -Headers @{'User-Agent'='DigitalXperts-Resizer';'Accept'='application/vnd.github+json'} -TimeoutSec 20
        } catch {
            if ($null -ne $_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) {
                return [pscustomobject]@{Available=$false;Version=$Metadata.version;Status='NoRelease'}
            }
            throw 'Nie mozna sprawdzic aktualizacji. Sprawdz polaczenie z internetem lub limit GitHub.'
        }
    }
    if ($Release.draft -or $Release.prerelease -or $Release.tag_name -notmatch '^v?(\d+\.\d+\.\d+)$') { throw 'Niepoprawne wydanie stabilne.' }
    $version = $Matches[1]
    if ([version]$version -le [version]$Metadata.version) { return [pscustomobject]@{Available=$false;Version=$version;Status='Current'} }
    $asset = @($Release.assets | Where-Object { $_.name -eq $Metadata.releaseAsset })
    if ($asset.Count -ne 1) { throw 'Wydanie nie zawiera paczki programu.' }
    $uri = [uri]$asset[0].browser_download_url
    $expectedPrefix = '/{0}/releases/download/' -f $Metadata.repository
    if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'github.com' -or -not $uri.AbsolutePath.StartsWith($expectedPrefix,[StringComparison]::Ordinal)) { throw 'Niepoprawne zrodlo paczki aktualizacji.' }
    $digestProperty = $asset[0].PSObject.Properties['digest']
    $digest = if ($null -ne $digestProperty) { [string]$digestProperty.Value } else { '' }
    $checksumAsset = @($Release.assets | Where-Object { $_.name -eq ($Metadata.releaseAsset + '.sha256') })
    if ($digest -notmatch '^sha256:[a-fA-F0-9]{64}$' -and $checksumAsset.Count -ne 1) { throw 'Brak sumy kontrolnej paczki.' }
    $checksumUrl = if ($checksumAsset.Count -eq 1) { [string]$checksumAsset[0].browser_download_url } else { '' }
    if ($checksumUrl) {
        $checksumUri = [uri]$checksumUrl
        if ($checksumUri.Scheme -ne 'https' -or $checksumUri.Host -ne 'github.com' -or -not $checksumUri.AbsolutePath.StartsWith($expectedPrefix,[StringComparison]::Ordinal)) { throw 'Niepoprawne zrodlo sumy kontrolnej.' }
    }
    return [pscustomobject]@{Available=$true;Version=$version;Status='Available';Url=$uri.AbsoluteUri;Digest=$digest;ChecksumUrl=$checksumUrl;Size=[long]$asset[0].size;ReleaseUrl=$Release.html_url}
}

function Expand-ResizerPackage {
    param([string]$ArchivePath,[string]$Destination)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $allowed = @(Get-ResizerManagedFiles) + @('package-manifest.json')
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        if ($archive.Entries.Count -ne $allowed.Count) { throw 'Niekompletna zawartosc ZIP.' }
        $seen = @()
        $totalSize = 0L
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -notin $allowed -or $entry.FullName -in $seen) { throw 'ZIP zawiera nieoczekiwane pliki lub sciezki.' }
            $seen += $entry.FullName
            $totalSize += $entry.Length
        }
        if ($totalSize -gt 100MB) { throw 'Paczka przekracza limit rozmiaru.' }
        [void](New-Item -ItemType Directory -Path $Destination -Force)
        foreach ($entry in $archive.Entries) {
            $target = Join-Path $Destination $entry.FullName
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$false)
        }
    } finally { $archive.Dispose() }
}

function Test-ResizerPackage {
    param([string]$Directory,[string]$ExpectedVersion)
    $manifest = Get-Content -LiteralPath (Join-Path $Directory 'package-manifest.json') -Raw | ConvertFrom-Json
    $metadata = Get-ResizerAppInfo -Directory $Directory
    if ($manifest.version -ne $ExpectedVersion -or $metadata.version -ne $ExpectedVersion) { throw 'Wersja paczki nie pasuje do wydania.' }
    $allowed = @(Get-ResizerManagedFiles)
    $properties = @($manifest.files.PSObject.Properties)
    if ($properties.Count -ne $allowed.Count) { throw 'Niekompletny manifest paczki.' }
    foreach ($file in $allowed) {
        $property = $manifest.files.PSObject.Properties[$file]
        $path = Join-Path $Directory $file
        if ($null -eq $property -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Brak pliku paczki: $file" }
        if ([string]$property.Value -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $property.Value) { throw "Niepoprawna suma kontrolna: $file" }
        if ([IO.Path]::GetExtension($file) -eq '.ps1') {
            $parseErrors = $null
            $parseTokens = $null
            [void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$parseTokens,[ref]$parseErrors)
            if ($parseErrors.Count -gt 0) { throw "Niepoprawna skladnia: $file" }
        }
    }
    return [pscustomobject]@{Version=$ExpectedVersion;Files=$allowed + @('package-manifest.json')}
}

function Save-ResizerUpdate {
    param($Candidate)
    $base = Join-Path $env:LOCALAPPDATA 'DigitalXperts\ResizerJPG\updates'
    $work = Join-Path $base ($Candidate.Version + '-' + [guid]::NewGuid())
    [void](New-Item -ItemType Directory -Path $work -Force)
    $archivePath = Join-Path $work 'release.zip'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $Candidate.Url -OutFile $archivePath -TimeoutSec 90 -Headers @{'User-Agent'='DigitalXperts-Resizer'}
    $expectedHash = if ($Candidate.Digest -match '^sha256:([a-fA-F0-9]{64})$') { $Matches[1] } else {
        $checksum = (Invoke-WebRequest -UseBasicParsing -Uri $Candidate.ChecksumUrl -TimeoutSec 20).Content
        if ($checksum -notmatch '^([a-fA-F0-9]{64})(?:\s|$)') { throw 'Niepoprawny plik sumy kontrolnej.' }
        $Matches[1]
    }
    if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ne $expectedHash) { throw 'Pobrana paczka ma niepoprawna sume kontrolna.' }
    $stage = Join-Path $work 'stage'
    Expand-ResizerPackage -ArchivePath $archivePath -Destination $stage
    [void](Test-ResizerPackage -Directory $stage -ExpectedVersion $Candidate.Version)
    return $stage
}
