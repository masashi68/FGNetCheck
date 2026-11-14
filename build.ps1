<#
build.ps1  配布用の FGNetCheck.bat と zip を作る（日本語版と英語版）

  powershell -ExecutionPolicy Bypass -File build.ps1 -Version 0.1.0

src\FGNetCheck.ps1 を bat の後ろに埋め込み、dist\ に 1 ファイルで出す。
bat は自分自身を読み、印から後ろを PowerShell のスクリプトとして実行する。一時ファイルは作らない。

  日本語版  dist\FGNetCheck.bat      zip には bat・使い方.txt・LICENSE.txt
  英語版    dist\en\FGNetCheck.bat   zip には bat・GUIDE.txt・LICENSE.txt

英語版は、本体の中の日本語の文字列を lang\en.txt の対訳で置き換えて作る。本体は 1 つだけ。
対訳が足りない・余っているときは、ビルドを止める。
#>
param(
    [string]$Version = 'dev'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
$src = Join-Path $root 'src\FGNetCheck.ps1'
$dist = Join-Path $root 'dist'
$utf8 = New-Object Text.UTF8Encoding $false

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
foreach ($line in ($head -split "`r?`n")) {
    if ($line -match '[^\x00-\x7F]') { throw "bat の頭に ASCII 以外の文字があります: $line" }
}

function Write-Bat([string]$script, [string]$out) {
    $text = ($head.TrimEnd() + "`r`n" + $marker + "`r`n" + $script) -replace "`r?`n", "`r`n"
    New-Item -ItemType Directory -Force (Split-Path -Parent $out) | Out-Null
    [IO.File]::WriteAllText($out, $text, $utf8)
    Write-Host "作りました: $out ($((Get-Item $out).Length) bytes)"
}

function Write-Zip([string]$zip, [string[]]$files) {
    if (Test-Path $zip) { Remove-Item $zip }
    Compress-Archive -Path $files -DestinationPath $zip
    Write-Host "作りました: $zip ($((Get-Item $zip).Length) bytes)"
}

# lang\en.txt を読む。「@@」の行で区切り、「=>」の行の前が元の文字列、後ろが訳
function Read-Translation([string]$path) {
    $map = @{}
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) -replace "`r`n", "`n"
    foreach ($block in ($text -split '(?m)^@@\n')) {
        if (-not $block.Trim()) { continue }
        $at = $block.IndexOf("`n=>`n")
        if ($at -lt 0) { throw "対訳の書式が違います: $block" }
        $from = $block.Substring(0, $at)
        $to = $block.Substring($at + 4).TrimEnd("`n")
        if ($map.ContainsKey($from)) { throw "対訳が重なっています: $from" }
        $map[$from] = $to
    }
    $map
}

# 日本語を含む字句を訳に置き換える。コメントは消す。位置がずれないよう、後ろから置き換える
function Convert-ToEnglish([string]$script, $map) {
    $script = $script -replace "`r`n", "`n"
    $tokens = $null; $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$tokens, [ref]$errs)
    if ($errs.Count -gt 0) { throw "本体に構文エラーがあります: $($errs[0].Message)" }
    $used = @{}
    $missing = New-Object System.Collections.Generic.List[string]
    $sb = New-Object Text.StringBuilder $script
    for ($i = $tokens.Count - 1; $i -ge 0; $i--) {
        $t = $tokens[$i]
        if ($t.Text -notmatch '[^\x00-\x7F]') { continue }
        $to = ''
        if ($t.Kind -ne 'Comment') {
            if (-not $map.ContainsKey($t.Text)) { $missing.Add("$($t.Extent.StartLineNumber) 行: $($t.Text)"); continue }
            $to = $map[$t.Text]
            $used[$t.Text] = $true
        }
        $start = $t.Extent.StartOffset
        [void]$sb.Remove($start, $t.Extent.EndOffset - $start).Insert($start, $to)
    }
    if ($missing.Count -gt 0) { throw "lang\en.txt に訳がありません:`n" + ($missing -join "`n") }
    $unused = @($map.Keys | Where-Object { -not $used.ContainsKey($_) })
    if ($unused.Count -gt 0) { throw "lang\en.txt に、もう使われていない訳があります:`n" + ($unused -join "`n") }
    $out = $sb.ToString()
    if ($out -match '[^\x00-\x7F]') { throw "英語版に ASCII 以外の文字が残っています: $($Matches[0])" }
    [void][System.Management.Automation.Language.Parser]::ParseInput($out, [ref]$tokens, [ref]$errs)
    if ($errs.Count -gt 0) { throw "英語版に構文エラーがあります（$($errs[0].Extent.StartLineNumber) 行）: $($errs[0].Message)" }
    $out
}

# 日本語版
$bat = Join-Path $dist 'FGNetCheck.bat'
Write-Bat $body $bat
Write-Zip (Join-Path $dist "FGNetCheck-$Version.zip") @($bat, (Join-Path $root '使い方.txt'), (Join-Path $root 'LICENSE.txt'))

# 英語版
$enDir = Join-Path $dist 'en'
$enBat = Join-Path $enDir 'FGNetCheck.bat'
Write-Bat (Convert-ToEnglish $body (Read-Translation (Join-Path $root 'lang\en.txt'))) $enBat
$guide = Join-Path $enDir 'GUIDE.txt'
Copy-Item (Join-Path $root 'GUIDE.en.txt') $guide -Force
Write-Zip (Join-Path $dist "FGNetCheck-$Version-en.zip") @($enBat, $guide, (Join-Path $root 'LICENSE.txt'))
