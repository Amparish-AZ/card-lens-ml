param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
    [string]$DatasetId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$DatasetVersion,

    [string]$Python = 'python'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Registry = Join-Path $ProjectRoot 'ml\data\registry'
$SourcePath = (Resolve-Path -LiteralPath $Source).Path

Push-Location $ProjectRoot
try {
    & $Python -m cardlens_ml validate-ner-dataset `
        --dataset $SourcePath `
        --require-images `
        --require-verified
    if ($LASTEXITCODE -ne 0) {
        throw 'The reviewed batch failed validation and was not registered.'
    }

    & $Python -m cardlens_ml register-ner-dataset `
        --source $SourcePath `
        --registry $Registry `
        --dataset-id $DatasetId `
        --dataset-version $DatasetVersion
    if ($LASTEXITCODE -ne 0) {
        throw 'Dataset registration failed.'
    }

    & $Python -m cardlens_ml list-ner-registry --registry $Registry
    if ($LASTEXITCODE -ne 0) {
        throw 'The aggregate registry failed validation.'
    }
}
finally {
    Pop-Location
}
