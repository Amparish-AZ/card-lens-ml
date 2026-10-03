param(
    [switch]$SkipOcr
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$python = Join-Path $project 'ml\.venv\Scripts\python.exe'
$dataset = Join-Path $project 'ml\data\private\roboflow_business_cards\Business-Card-1'
$models = Join-Path $project 'android\ppocr-sdk\src\main\assets\models'

if (-not (Test-Path -LiteralPath $python)) {
    throw "ML Python environment not found: $python"
}

$env:PYTHONPATH = Join-Path $project 'ml\src'

if (-not $SkipOcr) {
    & $python (Join-Path $project 'ml\scripts\run_desktop_ocr.py') `
        --images (Join-Path $dataset 'train') `
        --output (Join-Path $dataset 'ocr_output.jsonl') `
        --detector (Join-Path $models 'det\inference.onnx') `
        --recognizer (Join-Path $models 'rec\inference.onnx') `
        --recognizer-yaml (Join-Path $models 'rec\inference.yml')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

& $python (Join-Path $project 'ml\scripts\build_ner_draft.py') `
    --manifest (Join-Path $dataset 'source_manifest.jsonl') `
    --ocr (Join-Path $dataset 'ocr_output.jsonl') `
    --overrides (Join-Path $dataset 'semantic_overrides.json') `
    --output (Join-Path $dataset 'annotations\cards.jsonl') `
    --verified
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $python -m cardlens_ml validate-ner-dataset `
    --dataset $dataset `
    --require-images `
    --require-verified
exit $LASTEXITCODE
