param(
    [string[]]$OcrLanguages = @("jpn", "jpn_vert", "kor", "chi_sim", "chi_tra", "fra")
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "Installing Webtoon Lens local OCR/translation tools"
Write-Host ""

winget install --id tesseract-ocr.tesseract -e --accept-package-agreements --accept-source-agreements

$tessdata = Join-Path $env:LOCALAPPDATA "WebtoonLens\tessdata"
New-Item -ItemType Directory -Force -Path $tessdata | Out-Null

foreach ($language in $OcrLanguages) {
    $target = Join-Path $tessdata "$language.traineddata"
    Write-Host "Downloading Tesseract language: $language"
    Invoke-WebRequest -Uri "https://github.com/tesseract-ocr/tessdata_best/raw/main/$language.traineddata" -OutFile $target
}

$defaultTessdata = "C:\Program Files\Tesseract-OCR\tessdata"
foreach ($language in @("eng", "osd")) {
    $source = Join-Path $defaultTessdata "$language.traineddata"
    if (Test-Path $source) {
        Copy-Item -Force $source (Join-Path $tessdata "$language.traineddata")
    }
}

python -m pip install --user easyocr argostranslate transformers sentencepiece

@'
from argostranslate import package

needed = {("ja", "en"), ("ko", "en"), ("zh", "en"), ("en", "fr")}
package.update_package_index()
for pkg in package.get_available_packages():
    if (pkg.from_code, pkg.to_code) in needed:
        print(f"Installing Argos package {pkg.from_code}->{pkg.to_code}")
        package.install_from_path(pkg.download())

import easyocr
for langs in (["ja", "en"], ["ko", "en"], ["ch_sim", "en"], ["ch_tra", "en"], ["en"]):
    print("Preparing EasyOCR " + "+".join(langs))
    easyocr.Reader(langs, gpu=False, verbose=False)

from transformers import pipeline
print("Preparing English to French transformer")
pipeline("translation", model="Helsinki-NLP/opus-mt-en-fr", device=-1)
'@ | python -

Write-Host ""
Write-Host "Done. Restart the phone preview server after this install."
Write-Host ""
