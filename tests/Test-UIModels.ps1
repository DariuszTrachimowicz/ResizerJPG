$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
$modelFile = Join-Path $root 'ResizerUIModels.ps1'
if (-not (Test-Path -LiteralPath $modelFile)) { throw 'Photo queue model is not implemented.' }
. $modelFile
$photo = New-Object ResizerPhoto
$photo.FullPath = 'C:\Zdjecia\produkt.jpg'
$photo.Name = 'produkt.jpg'
$script:changes = New-Object 'Collections.Generic.List[string]'
$photo.add_PropertyChanged({ param($sender,$eventArgs) $script:changes.Add($eventArgs.PropertyName) })
if (-not $photo.IsIncluded) { throw 'New photos must be included by default.' }
$photo.IsIncluded = $false
$photo.Details = '1920 x 2880 px | Pion'
$photo.Status = 'Zapisano'
$photo.LastOutputPath = 'C:\Zdjecia\resize\produkt_R.jpg'
foreach ($property in @('IsIncluded','Details','Status','LastOutputPath')) {
    if ($property -notin $script:changes) { throw "Missing notification: $property" }
}
$count = $script:changes.Count
$photo.IsIncluded = $false
if ($script:changes.Count -ne $count) { throw 'Unchanged values must not raise duplicate notifications.' }
Write-Host 'PASS: photo inclusion, display and status notify WPF bindings.'
