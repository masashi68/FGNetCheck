<#
build.ps1  配布用の FGNetCheck.bat と zip を作る

  powershell -ExecutionPolicy Bypass -File build.ps1 -Version 0.1.0

src\FGNetCheck.ps1 を bat の後ろに埋め込み、dist\ に 1 ファイルで出す。
bat は自分自身を読み、印から後ろを PowerShell のスクリプトとして実行する。一時ファイルは作らない。
zip には bat・使い方.txt・LICENSE.txt を入れる。
#>
param(
    [string]$Version = 'dev'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
$src = Join-Path $root 'src\FGNetCheck.ps1'
$dist = Join-Path $root 'dist'
$out = Join-Path $dist 'FGNetCheck.bat'

$body = [IO.File]::ReadAllText($src, [Text.Encoding]::UTF8)
$marker = '#__FGNETCHECK_PS1__'
if ($body.Contains($marker)) { throw "スクリプトの中に印 $marker があります" }
$verLine = "`$AppVersion = 'dev'"
if (-not $body.Contains($verLine)) { throw "版番号の行が見つかりません: $verLine" }
$body = $body.Replace($verLine, "`$AppVersion = '$Version'")

# cmd が読む部分は ASCII だけにする（cmd は UTF-8 を正しく表示できず、BOM があると 1 行目が壊れる）。
# 印は分けて書き、この行自体が印として見つからないようにする
$head = @'
@echo off
setlocal
set "FGNC_BAT=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { Write-Host 'PowerShell is restricted on this PC by its administrator. FGNetCheck cannot run here.'; exit 1 }; $t = [IO.File]::ReadAllText($env:FGNC_BAT, [Text.Encoding]::UTF8); $i = $t.IndexOf('#__FGNETCHECK' + '_PS1__'); & ([ScriptBlock]::Create($t.Substring($i))) -Launcher $env:FGNC_BAT %*"
if errorlevel 1 pause
exit /b
'@

$text = ($head.TrimEnd() + "`r`n" + $marker + "`r`n" + $body) -replace "`r?`n", "`r`n"
foreach ($line in ($head -split "`r?`n")) {
    if ($line -match '[^\x00-\x7F]') { throw "bat の頭に ASCII 以外の文字があります: $line" }
}
New-Item -ItemType Directory -Force $dist | Out-Null
[IO.File]::WriteAllText($out, $text, (New-Object Text.UTF8Encoding $false))
Write-Host "作りました: $out ($((Get-Item $out).Length) bytes)"

$zip = Join-Path $dist "FGNetCheck-$Version.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path $out, (Join-Path $root '使い方.txt'), (Join-Path $root 'LICENSE.txt') -DestinationPath $zip
Write-Host "作りました: $zip ($((Get-Item $zip).Length) bytes)"
