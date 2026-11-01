<#
FGNetCheck.ps1  格闘ゲーム向け PC 設定チェック

  1. 診断      今の設定とおすすめの差、手作業の案内、起動・セキュリティの確認を表示する（何も変えない）
  2. 適用      おすすめ設定を入れる。変更前の値を backup フォルダに保存する
  3. 元に戻す  保存した値に戻す
  4. 測定      ping で遅延・ゆらぎ・ロスを測り、measure_log.txt に残す

配布版は FGNetCheck.bat の 1 ファイル（build.ps1 がこのファイルを bat に埋め込む）。
bat から動くときは -Launcher に bat のパスが渡り、backup などは bat の隣にできる。
#>
param(
    [ValidateSet('Menu', 'Diagnose', 'Apply', 'Restore', 'Measure')]
    [string]$Mode = 'Menu',
    [string]$BackupFile,
    [string]$Launcher
)

$ErrorActionPreference = 'Stop'
# build.ps1 が配布版の版番号に置き換える
$AppVersion = 'dev'

# 会社などで PowerShell が制限されている PC では動かせない。途中で失敗する前に止める
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Write-Host 'この PC は管理者の設定で PowerShell が制限されているため、このツールは使えません。' -ForegroundColor Red
    Read-Host 'Enter で閉じます' | Out-Null
    exit 1
}

$Here = if ($Launcher) { Split-Path -Parent $Launcher } else { Split-Path -Parent $PSCommandPath }
$BackupDir = Join-Path $Here 'backup'
$MeasureLog = Join-Path $Here 'measure_log.txt'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 変更する可能性があるモードは管理者で起動し直す
if ($Mode -in @('Menu', 'Apply', 'Restore') -and -not (Test-Admin)) {
    try {
        if ($Launcher) {
            # bat の中身は一時ファイルに書き出さず、bat を管理者で起動し直す
            Start-Process -FilePath $Launcher -Verb RunAs -ArgumentList "-Mode $Mode"
        } else {
            $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Mode $Mode"
            if ($BackupFile) { $argList += " -BackupFile `"$BackupFile`"" }
            Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
        }
    } catch {
        Write-Host '管理者として起動できませんでした。「はい」を選んでください。' -ForegroundColor Red
        Read-Host 'Enter で閉じます' | Out-Null
    }
    exit
}

# ---------------------------------------------------------------
# おすすめ設定の定義
# ---------------------------------------------------------------

# アダプターの省電力。RegistryKeyword で指定するので日本語ドライバーでも効く。
# 値 0 の表示名が「無効/オフ」でないものは触らない。
$AdvKeywords = @(
    @{ Key = '*EEE';                   Want = '0' },   # 省電力イーサネット（標準）
    @{ Key = 'AdvancedEEE';            Want = '0' },   # Realtek
    @{ Key = 'EnableGreenEthernet';    Want = '0' },   # Realtek
    @{ Key = 'GigaLite';               Want = '0' },   # Realtek
    @{ Key = 'EnableGigaLite';         Want = '0' },   # Realtek
    @{ Key = 'PowerSavingMode';        Want = '0' },   # Realtek
    @{ Key = 'EEELinkAdvertisement';   Want = '0' },   # Intel
    @{ Key = 'ReduceSpeedOnPowerDown'; Want = '0' },   # Intel
    @{ Key = 'ULPMode';                Want = '0' },   # Intel
    @{ Key = 'SipsEnabled';            Want = '0' },   # Intel
    @{ Key = '*SelectiveSuspend';      Want = '0' }    # USB 接続の LAN
)

$GroupName = @{
    A = 'アダプターの省電力を切る'
    B = '通信を Windows 既定に戻す'
    D = '電源プラン（電源接続時）'
    E = 'Windows のゲーム設定'
    F = '最適化ツールの残り (GPU)'
}

$WirelessSub = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'
$WirelessSetting = '12bbebe6-58d6-4636-95bb-3217ef867c1a'
$UsbSub = '2a737441-1930-4402-8d77-b2bebba308a3'
$UsbSuspendSetting = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
$DxPrefPath = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$PowerSaverPlan = 'a1841308-3541-4fab-bc81-f71556f20b4a'

# 最適化ツールが GraphicsDrivers に書き込む値。Windows も GPU ドライバーも既定では置かない。
# 多くは効果が確かめられず、割り込みや復旧を止めるものは固まりやすくなる。
# 実機で見つかったものを集めた。HwSchMode（GPU スケジューリング）は設定画面で選ぶものなので含めない
$GpuKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
$GpuTweakNames = @(
    'AdaptiveVsyncEnable', 'AllowDeepCStates', 'BuffersInFlight', 'ComputePreemption', 'ComputePreemptionLevel',
    'D3PCLatency', 'DefaultD3TransitionLatencyActivelyUsed', 'DefaultD3TransitionLatencyIdleLongTime',
    'DefaultD3TransitionLatencyIdleMonitorOff', 'DefaultD3TransitionLatencyIdleNoContext',
    'DefaultD3TransitionLatencyIdleShortTime', 'DefaultD3TransitionLatencyIdleVeryLongTime',
    'DefaultLatencyToleranceIdle0', 'DefaultLatencyToleranceIdle0MonitorOff', 'DefaultLatencyToleranceIdle1',
    'DefaultLatencyToleranceIdle1MonitorOff', 'DefaultLatencyToleranceMemory', 'DefaultLatencyToleranceMemoryNoContext',
    'DefaultLatencyToleranceNoContext', 'DefaultLatencyToleranceNoContextMonitorOff', 'DefaultLatencyToleranceOther',
    'DefaultLatencyToleranceTimerPeriod', 'DefaultMemoryRefreshLatencyToleranceActivelyUsed',
    'DefaultMemoryRefreshLatencyToleranceMonitorOff', 'DefaultMemoryRefreshLatencyToleranceNoContext',
    'Disable_OverlayDSQualityEnhancement', 'DisableAsyncPstates', 'DisableCudaContextPreemption', 'DisableDynamicPstate',
    'DisableGDIAcceleration', 'DisableKmRender', 'DisableKmRenderBoost', 'DisableOverclockedPstates', 'DisableOverlays',
    'DisablePFonDP', 'DisablePreemption', 'DisablePreemptionOnS3S4', 'DisableWriteCombining', 'DpiMapIommuContiguous',
    'EnableAggressivePStateBoost', 'EnableAggressivePStateOnly', 'EnableAsyncMidBufferPreemption', 'EnableCEPreemption',
    'EnableDirectFlip', 'EnableIndependentFlip', 'EnableMidBufferPreemption', 'EnableMidBufferPreemptionForHighTdrTimeout',
    'EnableMidGfxPreemption', 'EnableMidGfxPreemptionVGPU', 'EnablePerformanceMode', 'EnablePreemption',
    'EnableRuntimePowerManagement', 'EnableSCGMidBufferPreemption', 'EnableWDDM23Synchronization', 'F1TransitionLatency',
    'FlTransitionLatency', 'ForceDirectFlip', 'ForceFlipTrueImmediateMode', 'GPUPreemptionLevel', 'Latency', 'LOWLATENCY',
    'MaxIAverageGraphicsLatencyInOneBucket', 'MiracastPerfTrackGraphicsLatency', 'MonitorLatencyTolerance',
    'MonitorRefreshLatencyTolerance', 'Node3DLowLatency', 'PciLatencyTimerControl', 'PerfAnalyzeMidBufferPreemption',
    'PowerSavingTweaks', 'PreferSystemMemoryContiguous', 'PrimaryPushBufferSize', 'RmClkPowerOffDramPllWhenUnused',
    'RMDeepL1EntryLatencyUsec', 'RMDeepLlEntryLatencyUsec', 'RmDisableRegistryCaching', 'RMDisablePostL2Compression',
    'RmFbsrPagedDMA', 'RmGpsPsEnablePerCpuCoreDpc', 'TransitionLatency', 'UnsupportedMonitorModesAllowed', 'UseGpuTimer',
    'UseXPModel', 'VsyncIdleTimeout'
)

# GPU が固まったときの自動復旧 (TDR)。Microsoft の既定は TdrLevel=3、TdrDelay=2 秒。
# 復旧を止める・待ちを 0 にする値だけを戻す。計算用途で待ちを長くしている設定は残す
function Test-GpuTdrTweak([string]$name, $value) {
    switch ($name) {
        'TdrLevel' { return ([int]$value -ne 3) }
        'TdrDelay' { return ([int]$value -lt 2) }
        default    { return ($name -like 'Tdr*' -and [int]$value -eq 0) }
    }
}

# マウス設定をログオンし直さずに反映するため
try {
    Add-Type -Namespace FGNetCheck -Name MouseApi -MemberDefinition '[DllImport("user32.dll", SetLastError = true)] public static extern bool SystemParametersInfo(uint action, uint param, int[] values, uint winIni);'
} catch { }
$EfficiencyOverlay = '961cc777-2547-4f9d-8174-7d86181b8a7a'

function Get-ActivePlan {
    $o = (cmd /c 'powercfg /getactivescheme') -join ' '
    if ($o -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s*\((.+)\)') {
        return [pscustomobject]@{ Guid = $Matches[1].ToLower(); Name = $Matches[2].Trim() }
    }
    return $null
}

function Get-PlanArg($s) {
    # 古い保存データには Scheme が無いので今のプランを使う
    if ($s.Scheme) { $s.Scheme } else { 'SCHEME_CURRENT' }
}

function Get-TargetAdapters {
    # 有線 (802.3 = 14) と Wi-Fi (802.11 = 9) の実物だけ。仮想・VPN は触らない
    @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.NdisPhysicalMedium -in @(9, 14) -and $_.Status -ne 'Disabled' })
}

function Get-MediaLabel($a) {
    if ($a.NdisPhysicalMedium -eq 14) { '有線' } else { 'Wi-Fi' }
}

function Resolve-AdapterName($guid) {
    $a = Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceGuid -eq $guid } | Select-Object -First 1
    if ($a) { $a.Name } else { $null }
}

function Format-Val($v) {
    if ($null -eq $v -or "$v" -eq '') { '(なし)' } else { "$v" }
}

function Get-Settings {
    $list = New-Object System.Collections.Generic.List[object]
    $pmCmd = Get-Command Set-NetAdapterPowerManagement -ErrorAction SilentlyContinue
    $pmHasAllow = $pmCmd -and $pmCmd.Parameters.ContainsKey('AllowComputerToTurnOffDevice')
    $hasWifi = $false

    foreach ($a in Get-TargetAdapters) {
        $target = "$($a.Name) ($(Get-MediaLabel $a))"
        if ($a.NdisPhysicalMedium -eq 9) { $hasWifi = $true }

        # A: 省電力
        $props = @(Get-NetAdapterAdvancedProperty -Name $a.Name -ErrorAction SilentlyContinue)
        foreach ($k in $AdvKeywords) {
            $p = $props | Where-Object { $_.RegistryKeyword -eq $k.Key } | Select-Object -First 1
            if (-not $p) { continue }
            $idx = [array]::IndexOf(@($p.ValidRegistryValues), $k.Want)
            if ($idx -lt 0) { continue }
            $disp = @($p.ValidDisplayValues)[$idx]
            if ($disp -notmatch 'disab|off|無効|オフ') { continue }
            $list.Add([pscustomobject]@{
                Id = "adv|$($a.InterfaceGuid)|$($k.Key)"; Group = 'A'; Label = $p.DisplayName; Target = $target
                Kind = 'adv'; Guid = $a.InterfaceGuid; Key = $k.Key; Want = $k.Want; WantText = $disp; OkMode = 'eq'
            })
        }
        if ($pmHasAllow) {
            $pm = Get-NetAdapterPowerManagement -Name $a.Name -ErrorAction SilentlyContinue
            if ($pm -and "$($pm.AllowComputerToTurnOffDevice)" -in @('Enabled', 'Disabled')) {
                $list.Add([pscustomobject]@{
                    Id = "pm|$($a.InterfaceGuid)"; Group = 'A'; Label = '電力の節約のために電源をオフ'; Target = $target
                    Kind = 'pm'; Guid = $a.InterfaceGuid; Want = 'Disabled'; WantText = 'Disabled'; OkMode = 'eq'
                })
            }
        }

        # B: 大きな送信のオフロード（既定は有効。切ると CPU 負荷が増える）
        if (Get-NetAdapterLso -Name $a.Name -ErrorAction SilentlyContinue) {
            foreach ($v in @('IPv4', 'IPv6')) {
                $list.Add([pscustomobject]@{
                    Id = "lso|$($a.InterfaceGuid)|$v"; Group = 'B'; Label = "大きな送信のオフロード ($v)"; Target = $target
                    Kind = 'lso'; Guid = $a.InterfaceGuid; Key = $v; Want = 'True'; WantText = 'True (既定)'; OkMode = 'eq'
                })
            }
        }
    }

    # B: Windows 全体
    $list.Add([pscustomobject]@{
        Id = 'rsc'; Group = 'B'; Label = '受信セグメントの結合 (RSC)'; Target = 'Windows 全体'
        Kind = 'rsc'; Want = 'Enabled'; WantText = 'Enabled (既定)'; OkMode = 'eq'
    })
    $list.Add([pscustomobject]@{
        Id = 'tcp|CongestionProvider'; Group = 'B'; Label = '輻輳制御'; Target = 'TCP (Internet)'
        Kind = 'tcp'; Prop = 'CongestionProvider'; Want = 'CUBIC'; WantText = 'CUBIC (既定)'; OkMode = 'eq'
    })
    $list.Add([pscustomobject]@{
        Id = 'tcp|InitialRtoMs'; Group = 'B'; Label = '最初の再送までの待ち (ms)'; Target = 'TCP (Internet)'
        Kind = 'tcp'; Prop = 'InitialRtoMs'; Want = '1000'; WantText = '1000 以下 (既定 1000)'; OkMode = 'le'
    })

    # D: 電源プラン（電源接続時 = AC だけ。バッテリー時は変えない）
    # プランの GUID を記録し、元に戻すときに別のプランを書き換えないようにする
    $plan = Get-ActivePlan
    $planTarget = if ($plan) { "電源プラン: $($plan.Name)" } else { '今の電源プラン' }
    $planId = if ($plan) { $plan.Guid } else { $null }
    $pcfgItems = @(
        @{ Id = 'ASPM';        Label = 'PCI Express の省電力';     Sub = 'SUB_PCIEXPRESS'; Setting = 'ASPM';             Want = '0';   WantText = '0 (オフ)';                 OkMode = 'eq' },
        @{ Id = 'UsbSuspend';  Label = 'USB のセレクティブ サスペンド'; Sub = $UsbSub;          Setting = $UsbSuspendSetting; Want = '0';   WantText = '0 (無効)';                 OkMode = 'eq' },
        @{ Id = 'ProcMax';     Label = 'CPU の最大の状態 (%)';      Sub = 'SUB_PROCESSOR';  Setting = 'PROCTHROTTLEMAX';  Want = '100'; WantText = '100';                      OkMode = 'eq' },
        @{ Id = 'Boost';       Label = 'CPU のブースト';            Sub = 'SUB_PROCESSOR';  Setting = 'PERFBOOSTMODE';    Want = '2';   WantText = '0 (無効) 以外。直すなら 2'; OkMode = 'notZero' }
    )
    if ($hasWifi) {
        $pcfgItems += @{ Id = 'Wireless'; Label = 'ワイヤレス アダプターの省電力'; Sub = $WirelessSub; Setting = $WirelessSetting; Want = '0'; WantText = '0 (最大パフォーマンス)'; OkMode = 'eq' }
    }
    foreach ($p in $pcfgItems) {
        $list.Add([pscustomobject]@{
            Id = "pcfg|$($p.Id)"; Group = 'D'; Label = $p.Label; Target = $planTarget
            Kind = 'pcfg'; Scheme = $planId; Sub = $p.Sub; Setting = $p.Setting; Want = $p.Want; WantText = $p.WantText; OkMode = $p.OkMode
        })
    }

    # E: ゲームモード（値が無いときはオン扱い。0 のときだけ直す）
    # 管理者に昇格しても同じアカウントなら HKCU は本人のもの
    $list.Add([pscustomobject]@{
        Id = 'reg|GameMode'; Group = 'E'; Label = 'ゲームモード'; Target = 'このユーザー'
        Kind = 'reg'; Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'AutoGameModeEnabled'
        Want = '1'; WantText = '1 (オン。未設定もオン)'; OkMode = 'notZero'
    })

    # E: ポインターの精度を高める（マウス加速）。ゲームの照準や移動量がぶれる
    $list.Add([pscustomobject]@{
        Id = 'mouse|Acceleration'; Group = 'E'; Label = 'ポインターの精度を高める'; Target = 'このユーザー'
        Kind = 'mouse'; Want = '0,0,0'; WantText = 'オフ (0,0,0)'; OkMode = 'mouseOff'
    })

    # F: 最適化ツールが GPU の設定に残した値。ある値だけを並べ、消すと一覧から消える
    foreach ($sub in @('', 'Power', 'Scheduler')) {
        $path = if ($sub) { "$GpuKey\$sub" } else { $GpuKey }
        $k = Get-Item -Path $path -ErrorAction SilentlyContinue
        if (-not $k) { continue }
        foreach ($n in $k.GetValueNames()) {
            if (-not $n) { continue }
            $type = "$($k.GetValueKind($n))"
            # 元に戻せる型だけ扱う
            if ($type -notin @('DWord', 'QWord', 'String')) { continue }
            $v = $k.GetValue($n)
            $isTdr = $n -like 'Tdr*' -and $type -ne 'String' -and -not $sub
            if (-not (($n -in $GpuTweakNames) -or ($isTdr -and (Test-GpuTdrTweak $n $v)))) { continue }
            $where = if ($sub) { "GPU 設定 ($sub)" } else { 'GPU 設定' }
            $list.Add([pscustomobject]@{
                Id = "regraw|$sub|$n"; Group = 'F'; Label = $n; Target = $where
                Kind = 'regraw'; Path = $path; Name = $n; RegType = $type; Want = ''; WantText = '(なし) 既定'; OkMode = 'absent'
            })
        }
    }
    $list
}

# DirectXUserGlobalSettings は "Key=Value;Key=Value;" の 1 本の文字列。ほかのキーは残す
function Get-DxSetting($raw, [string]$key) {
    if (-not $raw) { return $null }
    foreach ($part in ("$raw" -split ';')) {
        $kv = $part -split '=', 2
        if ($kv.Count -eq 2 -and $kv[0] -eq $key) { return $kv[1] }
    }
    return $null
}

# ---------------------------------------------------------------
# 読む・書く
# ---------------------------------------------------------------

function Get-Value($s) {
    switch ($s.Kind) {
        'adv' {
            $n = Resolve-AdapterName $s.Guid
            if (-not $n) { return $null }
            $p = Get-NetAdapterAdvancedProperty -Name $n -RegistryKeyword $s.Key -ErrorAction SilentlyContinue
            if ($p) { return "$(@($p.RegistryValue)[0])" }
            return $null
        }
        'pm' {
            $n = Resolve-AdapterName $s.Guid
            if (-not $n) { return $null }
            return "$((Get-NetAdapterPowerManagement -Name $n).AllowComputerToTurnOffDevice)"
        }
        'lso' {
            $n = Resolve-AdapterName $s.Guid
            if (-not $n) { return $null }
            $l = Get-NetAdapterLso -Name $n
            return "$($l.("$($s.Key)Enabled"))"
        }
        'rsc' { return "$((Get-NetOffloadGlobalSetting).ReceiveSegmentCoalescing)" }
        'tcp' {
            # 管理者でないと空で返る項目がある
            $v = "$((Get-NetTCPSetting -SettingName Internet).($s.Prop))"
            if ($v -eq '') { return $null }
            return $v
        }
        'reg' {
            $v = Get-ItemProperty -Path $s.Path -Name $s.Name -ErrorAction SilentlyContinue
            if ($null -eq $v) { return $null }
            return "$($v.($s.Name))"
        }
        'regraw' {
            $k = Get-Item -Path $s.Path -ErrorAction SilentlyContinue
            if (-not $k -or $s.Name -notin $k.GetValueNames()) { return $null }
            return "$($k.GetValue($s.Name))"
        }
        'mouse' {
            $p = Get-ItemProperty -Path 'HKCU:\Control Panel\Mouse'
            return "$($p.MouseSpeed),$($p.MouseThreshold1),$($p.MouseThreshold2)"
        }
        'pcfg' {
            $out = (cmd /c "powercfg /qh $(Get-PlanArg $s) $($s.Sub) $($s.Setting) 2>nul") -join "`n"
            # 最後の 2 つの 0x 値が AC (電源接続時) と DC (バッテリー)
            $m = [regex]::Matches($out, '0x([0-9a-fA-F]{8})')
            if ($m.Count -lt 2) { return $null }
            return "$([Convert]::ToInt32($m[$m.Count - 2].Groups[1].Value, 16))"
        }
    }
}

function Invoke-NoRestart([string]$cmd, [hashtable]$sp) {
    if ((Get-Command $cmd).Parameters.ContainsKey('NoRestart')) { $sp['NoRestart'] = $true }
    & $cmd @sp
}

function Set-Value($s, $value) {
    switch ($s.Kind) {
        'adv' {
            $n = Resolve-AdapterName $s.Guid
            if (-not $n) { throw 'アダプターが見つかりません' }
            Set-NetAdapterAdvancedProperty -Name $n -RegistryKeyword $s.Key -RegistryValue $value -NoRestart
        }
        'pm' {
            $n = Resolve-AdapterName $s.Guid
            if (-not $n) { throw 'アダプターが見つかりません' }
            Invoke-NoRestart 'Set-NetAdapterPowerManagement' @{ Name = $n; AllowComputerToTurnOffDevice = $value }
        }
        'lso' {
            $n = Resolve-AdapterName $s.Guid
            if (-not $n) { throw 'アダプターが見つかりません' }
            Invoke-NoRestart 'Set-NetAdapterLso' @{ Name = $n; ("$($s.Key)Enabled") = [bool]::Parse("$value") }
        }
        'rsc' { Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing $value }
        'tcp' {
            if ($s.Prop -eq 'CongestionProvider') {
                Set-NetTCPSetting -SettingName Internet -CongestionProvider $value
            } else {
                Set-NetTCPSetting -SettingName Internet -InitialRto ([int]$value)
            }
        }
        'reg' {
            if ($null -eq $value -or "$value" -eq '') {
                Remove-ItemProperty -Path $s.Path -Name $s.Name -ErrorAction SilentlyContinue
            } else {
                if (-not (Test-Path $s.Path)) { New-Item -Path $s.Path -Force | Out-Null }
                New-ItemProperty -Path $s.Path -Name $s.Name -PropertyType DWord -Value ([int]$value) -Force | Out-Null
            }
        }
        'regraw' {
            # 消すのが既定。元に戻すときは保存した型で書き直す
            if ($null -eq $value -or "$value" -eq '') {
                Remove-ItemProperty -Path $s.Path -Name $s.Name -ErrorAction SilentlyContinue
            } else {
                $typed = switch ($s.RegType) {
                    'DWord'  { [int]$value }
                    'QWord'  { [long]$value }
                    default  { "$value" }
                }
                New-ItemProperty -Path $s.Path -Name $s.Name -PropertyType $s.RegType -Value $typed -Force | Out-Null
            }
        }
        'mouse' {
            # 値の並びは 速度,しきい値1,しきい値2。SPI_SETMOUSE は しきい値1,しきい値2,速度 の順
            $v = @("$value" -split ',' | ForEach-Object { [int]$_ })
            if ($v.Count -ne 3) { throw "マウスの値が不正です: $value" }
            # 4 = SPI_SETMOUSE、3 = レジストリへ保存して全体に通知
            if (-not [FGNetCheck.MouseApi]::SystemParametersInfo(4, 0, [int[]]@($v[1], $v[2], $v[0]), 3)) {
                throw 'マウス設定を変更できませんでした'
            }
        }
        'pcfg' {
            $planArg = Get-PlanArg $s
            cmd /c "powercfg /setacvalueindex $planArg $($s.Sub) $($s.Setting) $value" | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'powercfg が失敗しました' }
            # 使用中のプランなら読み込み直して反映する。使っていないプランは切り替えない
            $active = Get-ActivePlan
            if ($planArg -eq 'SCHEME_CURRENT' -or ($active -and $active.Guid -eq $planArg)) {
                cmd /c "powercfg /setactive $planArg" | Out-Null
            }
        }
    }
}

function Test-Ok($s, $cur) {
    switch ($s.OkMode) {
        'le'      { return ([int]$cur -le [int]$s.Want) }
        'notZero' { return ("$cur" -ne '0') }
        'mouseOff' { return (("$cur" -split ',')[0] -eq '0') }
        'absent'  { return ("$cur" -eq '') }
        default   { return ("$cur" -eq "$($s.Want)") }
    }
}

function Get-State {
    foreach ($s in Get-Settings) {
        $cur = $null
        try { $cur = Get-Value $s } catch { $cur = $null }
        # 値が読めないものは、この PC には無い設定として外す（レジストリの「無し」は除く）
        if ($null -eq $cur -and $s.Kind -ne 'reg') { continue }
        $s | Add-Member -NotePropertyName Current -NotePropertyValue $cur -Force
        $s | Add-Member -NotePropertyName Ok -NotePropertyValue (Test-Ok $s $cur) -Force
        $s
    }
}

# ---------------------------------------------------------------
# 画面
# ---------------------------------------------------------------

function Show-Adapters {
    Write-Host ''
    Write-Host '■ ネットワークアダプター' -ForegroundColor Cyan
    foreach ($a in Get-TargetAdapters) {
        Write-Host ("  {0} [{1}] 状態:{2} 速度:{3}  {4}" -f $a.Name, (Get-MediaLabel $a), $a.Status, $a.LinkSpeed, $a.InterfaceDescription)
    }
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric | Select-Object -First 1
    if ($route) {
        Write-Host "  インターネットに使っているもの: $($route.InterfaceAlias)"
        $used = Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue
        if ($used -and $used.NdisPhysicalMedium -eq 9) {
            Write-Host '  注意: Wi-Fi でつないでいます。格闘ゲームのオンライン対戦では、揺れやロスが巻き戻りやカクつきになって出ます。有線 LAN にするのがいちばん効きます。' -ForegroundColor Yellow
        }
    }
}

function Show-Plan($state) {
    $rows = foreach ($s in $state) {
        [pscustomobject]@{
            区分     = $GroupName[$s.Group]
            項目     = $s.Label
            対象     = $s.Target
            今       = Format-Val $s.Current
            おすすめ = $s.WantText
            判定     = $(if ($s.Ok) { 'OK' } else { '変更する' })
        }
    }
    $rows | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host
}

function Get-RegValue([string]$path, [string]$name) {
    $v = Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
    if ($null -eq $v) { return $null }
    return $v.$name
}

function Write-Check([string]$level, [string]$text, [string]$fix) {
    $color = switch ($level) { 'OK' { 'Green' } '注意' { 'Yellow' } default { 'Gray' } }
    Write-Host ("  [{0}] {1}" -f $level, $text) -ForegroundColor $color
    if ($fix) { Write-Host "         → $fix" }
}

# ② 自動では変えず、やり方を案内するもの
function Show-Advice {
    Write-Host ''
    Write-Host '■ 手作業で確かめてほしいこと（ツールは変えません）' -ForegroundColor Cyan

    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $isLaptop = $cs -and $cs.PCSystemType -eq 2
    if ($isLaptop) {
        $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
        $onAc = (-not $bat) -or $bat.BatteryStatus -eq 2
        if ($onAc) {
            Write-Check '情報' 'ノート PC（電源に接続中）です。' '熱で CPU が自動で遅くなることがあります。メーカーの電源・冷却アプリで性能寄りか冷却寄りのモードを選んでください。'
        } else {
            Write-Check '注意' 'ノート PC がバッテリーで動いています。' 'ゲームは電源につないで遊んでください。このツールの電源設定は電源接続時だけを変えます。'
        }
    }

    # プランの切り替えはメーカー独自プランもあるので案内だけにする
    $plan = Get-ActivePlan
    if ($plan -and $plan.Guid -eq $PowerSaverPlan) {
        Write-Check '注意' "電源プランが「$($plan.Name)」です。CPU が抑えられます。" 'コントロール パネル → 電源オプション で「バランス」か「高パフォーマンス」を選んでください。'
    } elseif ($plan) {
        Write-Check 'OK' "電源プラン: $($plan.Name)"
    }
    $overlay = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' 'ActiveOverlayAcPowerScheme'
    if ("$overlay" -eq $EfficiencyOverlay) {
        Write-Check '注意' '電源モード（電源接続時）が「最適な電力効率」です。' '設定 → システム → 電源 → 電源モード を「最適なパフォーマンス」にしてください。'
    }

    # ウィンドウ表示のゲームの最適化。効くのは DirectX 10/11 のゲームだけで、
    # Lossless Scaling との併用でフリーズする報告があるので自動では変えない
    $swap = Get-DxSetting (Get-RegValue $DxPrefPath 'DirectXUserGlobalSettings') 'SwapEffectUpgradeEnable'
    if ("$swap" -eq '1') {
        Write-Check '情報' 'ウィンドウ表示のゲームの最適化: オン' 'Lossless Scaling などの使用中に固まるときは、設定 → ディスプレイ → グラフィック → 既定のグラフィック設定 でオフにしてください。'
    } else {
        Write-Check '情報' 'ウィンドウ表示のゲームの最適化: オフ' 'DirectX 10/11 のゲームをウィンドウ・ボーダーレスで遊ぶなら試す価値があります。Lossless Scaling と併用するとフリーズする報告があります。'
    }

    # ドライブの定期最適化。HDD は止めると遅くなる。SSD は削除のたびに TRIM が送られていれば影響は小さい
    $disks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
    $hasHdd = @($disks | Where-Object { "$($_.MediaType)" -eq 'HDD' }).Count -gt 0
    $defrag = Get-ScheduledTask -TaskPath '\Microsoft\Windows\Defrag\' -TaskName 'ScheduledDefrag' -ErrorAction SilentlyContinue
    $trimOff = ((cmd /c 'fsutil behavior query DisableDeleteNotify') -join "`n") -match 'NTFS DisableDeleteNotify\s*=\s*1'
    if ($trimOff) {
        Write-Check '注意' 'SSD への TRIM が止められています。書き込みが遅くなっていくことがあります。' '管理者で: fsutil behavior set DisableDeleteNotify 0'
    }
    if ($defrag -and "$($defrag.State)" -eq 'Disabled') {
        if ($hasHdd) {
            Write-Check '注意' 'HDD があるのに、ドライブの定期最適化が止まっています。' 'スタートで「ドライブのデフラグと最適化」→ 設定の変更 → スケジュールに従って実行する をオンにしてください。'
        } else {
            Write-Check '情報' 'ドライブの定期最適化が止まっています。SSD だけで TRIM が有効なら、影響は小さいです。'
        }
    }

    # SysMain（先読み）。SSD では効果が小さく、HDD では読み込みが速くなることがある
    $sysMain = Get-Service -Name SysMain -ErrorAction SilentlyContinue
    if ($sysMain -and "$($sysMain.StartType)" -eq 'Disabled') {
        if ($hasHdd) {
            Write-Check '情報' 'SysMain (アプリの先読み) が止まっています。HDD では既定の自動起動に戻すと読み込みが速くなることがあります。'
        } else {
            Write-Check '情報' 'SysMain (アプリの先読み) が止まっています。SSD だけなら影響は小さいです。'
        }
    }

    $vendor = @(Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'Running' -and $_.DisplayName -match 'Killer|SmartByte|cFos|Rivet' })
    if ($vendor.Count -gt 0) {
        $names = ($vendor | ForEach-Object { $_.DisplayName }) -join ', '
        # サービスが動いていても、アプリ側で優先制御をオフにしていれば問題ない。その設定は外から読めないので情報にとどめる
        Write-Check '情報' "メーカーの通信制御ソフトが入っています: $names" 'そのソフトで通信の優先制御・帯域管理がオフになっているか確かめてください。オフならこのままで問題ありません。'
    } else {
        Write-Check 'OK' 'メーカーの通信制御ソフトは見つかりません。'
    }

    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
    foreach ($g in $gpus) {
        # ドライバーの古さ。300 日を超えたら更新を勧める
        if ($g.DriverDate) {
            $days = [int]((Get-Date) - $g.DriverDate).TotalDays
            $when = $g.DriverDate.ToString('yyyy-MM-dd')
            if ($days -gt 300) {
                # PC メーカーのページの版は GPU メーカーより古いことが多く、入れると戻ってしまう
                if ($g.Name -match 'NVIDIA|AMD|Radeon') {
                    $fix = 'NVIDIA / AMD の公式サイト（または NVIDIA App / AMD Software）から最新版を入れてください。PC メーカーのページの版は古いことが多いです。'
                } else {
                    $fix = 'Intel の古い世代の内蔵 GPU は更新が止まっていることがあります。Intel の公式サイトで、その CPU 向けの最新版がこれより新しいか確かめてください。'
                }
                Write-Check '注意' "$($g.Name) のドライバーが古めです（$when、約 $days 日前、版 $($g.DriverVersion)）。" $fix
            } else {
                Write-Check 'OK' "$($g.Name) のドライバー: $when"
            }
        }
        # 画面のリフレッシュレート。最大より低いと滑らかさと遅延が損をする
        if ($g.CurrentRefreshRate -gt 1 -and $g.MaxRefreshRate -gt $g.CurrentRefreshRate) {
            Write-Check '注意' "$($g.Name) の画面が $($g.CurrentRefreshRate)Hz で動いています（最大 $($g.MaxRefreshRate)Hz）。" '設定 → ディスプレイ → ディスプレイの詳細設定 → リフレッシュ レート で最大を選んでください。'
        } elseif ($g.CurrentRefreshRate -gt 1) {
            Write-Check 'OK' "$($g.Name) の画面: $($g.CurrentRefreshRate)Hz"
        }
    }

    # アプリごとの GPU の割り当て（GPU が 2 つ以上あるときだけ意味がある）
    if ($gpus.Count -ge 2) {
        $prefNames = @{ '0' = 'Windows に任せる'; '1' = '省電力'; '2' = '高パフォーマンス' }
        $pref = Get-ItemProperty -Path $DxPrefPath -ErrorAction SilentlyContinue
        $apps = @()
        if ($pref) {
            $apps = @($pref.PSObject.Properties | Where-Object { $_.Name -match '\\.+\.exe$' })
        }
        if ($apps.Count -eq 0) {
            Write-Check '情報' ("GPU が {0} つあります。" -f $gpus.Count) '設定 → ディスプレイ → グラフィック で、ゲームを「高パフォーマンス」にしてください。'
        }
        foreach ($a in $apps) {
            $exe = Split-Path $a.Name -Leaf
            $val = "$($a.Value)"
            if ($val -notmatch '^([A-Za-z]+=[^;=]*;)+$') {
                Write-Check '注意' "$exe の GPU 設定の値が壊れている可能性があります。" '設定 → ディスプレイ → グラフィック でこのアプリを選び、設定し直してください。'
                continue
            }
            $p = Get-DxSetting $val 'GpuPreference'
            $name = if ($prefNames.ContainsKey("$p")) { $prefNames["$p"] } else { "不明 ($p)" }
            Write-Check '情報' "$exe の GPU: $name"
        }
    }

    # Wi-Fi で使っているときは電波の強さを見る
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
    $used = if ($route) { Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue } else { $null }
    if ($used -and $used.NdisPhysicalMedium -eq 9) {
        $sig = $null
        $wl = (cmd /c 'netsh wlan show interfaces') -join "`n"
        if ($wl -match '(\d{1,3})\s*%') { $sig = [int]$Matches[1] }
        if ($null -ne $sig -and $sig -lt 70) {
            Write-Check '注意' "Wi-Fi の電波が弱めです（$sig%）。" 'ルーターに近づく、5GHz / 6GHz を使う、有線 LAN にする、のどれかが効きます。'
        } elseif ($null -ne $sig) {
            Write-Check 'OK' "Wi-Fi の電波: $sig%"
        }
        Write-Check '情報' '数十秒おきに ping が跳ねるときは、Wi-Fi の周辺スキャンが原因のことがあります。' 'Wi-Fi ドライバーの更新と、ルーターのローミング・背景スキャンの設定を確認してください。'
    }

    Write-Check '情報' 'P2P で対戦するゲームでつながりにくい・相手が限られるときは、ルーター側の設定が原因のことがあります。' 'ルーターの UPnP を有効にするか、ゲームの案内に従ってポートを開けてください（ツールからは確認できません）。'

    $startup = @()
    foreach ($runKey in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')) {
        $rk = Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue
        if ($rk) { $startup += @($rk.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { $_.Name }) }
    }
    if ($startup.Count -gt 0) {
        Write-Check '情報' ("起動時に動くアプリ ({0}): {1}" -f $startup.Count, ($startup -join ', ')) 'ゲーム中に要らないものは タスク マネージャー → スタートアップ アプリ で無効にできます。'
    }

    # 対戦ゲームの通信を止めるブロック規則。P2P の対戦では、つながらない・相手が限られる原因になる。
    # ゲームの exe 名は作品ごとに違うので、置き場所（Steam のゲームフォルダ・Fightcade）で見分ける
    $fgPattern = '\\steamapps\\common\\|fightcade|\\fcade[^\\]*\.exe$|fbneo|flycast|ggpo'
    $allBlock = @(Get-NetFirewallRule -Action Block -Enabled True -ErrorAction SilentlyContinue)
    $fgBlocked = @{}
    foreach ($r in $allBlock) {
        $prog = ($r | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue).Program
        if (-not $prog -or $prog -eq 'Any' -or $prog -notmatch $fgPattern) { continue }
        $key = $prog.ToLower()
        if (-not $fgBlocked.ContainsKey($key)) { $fgBlocked[$key] = [pscustomobject]@{ Program = $prog; Where = @() } }
        $dir = if ("$($r.Direction)" -eq 'Inbound') { '受信' } else { '送信' }
        $fgBlocked[$key].Where += @("$($r.Profile)" -split ',\s*' | ForEach-Object { "$dir/$_" })
    }
    if ($fgBlocked.Count -gt 0) {
        foreach ($b in $fgBlocked.Values) {
            $w = (@($b.Where) | Sort-Object -Unique) -join ', '
            Write-Check '注意' "対戦ゲームの通信がブロックされています: $($b.Program)（$w）" '使っているゲームなら、Windows セキュリティ → ファイアウォールとネットワーク保護 → 詳細設定 → 受信の規則（と送信の規則）でこのブロック規則を消し、ゲームを起動し直して「許可」してください。'
        }
    } else {
        Write-Check 'OK' '対戦ゲーム（Steam・Fightcade）の通信をブロックする規則はありません。'
    }

    # ファイアウォールの確認画面で「キャンセル」すると、そのアプリの受信をブロックする規則ができる。
    # Windows 標準の規則（グループ付き）と、上で出した対戦ゲームは除く
    $blocked = @{}
    foreach ($r in @($allBlock | Where-Object { "$($_.Direction)" -eq 'Inbound' -and -not $_.Group })) {
        $prog = ($r | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue).Program
        if (-not $prog -or $prog -eq 'Any' -or $prog -match $fgPattern) { continue }
        $key = $prog.ToLower()
        if (-not $blocked.ContainsKey($key)) { $blocked[$key] = [pscustomobject]@{ Program = $prog; Profiles = @() } }
        $blocked[$key].Profiles += "$($r.Profile)"
    }
    if ($blocked.Count -gt 0) {
        foreach ($b in $blocked.Values) {
            $prof = (@($b.Profiles | ForEach-Object { $_ -split ',\s*' }) | Sort-Object -Unique) -join ', '
            Write-Check '注意' "受信をブロックされているアプリ: $($b.Program)（$prof）"
        }
        Write-Host '         → ゲームや通話のアプリなら、Windows セキュリティ → ファイアウォールとネットワーク保護 → 詳細設定 → 受信の規則 でそのブロック規則を消し、アプリを起動し直して「許可」してください。使わないアプリならそのままで構いません。'
    } else {
        Write-Check 'OK' 'ファイアウォールで受信をブロックされているアプリはありません。'
    }

    # メモリ。1 枚だとシングルチャネルで性能が落ちる。定格より遅いときは XMP/EXPO か CPU の上限
    $mem = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    if ($mem.Count -gt 0) {
        $totalGb = [math]::Round((($mem | Measure-Object Capacity -Sum).Sum) / 1GB)
        if ($mem.Count -eq 1) {
            Write-Check '注意' "メモリが 1 枚 (${totalGb}GB) です。シングルチャネルになり、ゲームの性能が落ちることがあります。" '同じ容量・同じ速さのメモリをもう 1 枚足すとデュアルチャネルになります（ノート PC は増設できるか仕様を確認してください）。'
        } else {
            Write-Check 'OK' "メモリ: $($mem.Count) 枚 (${totalGb}GB)"
        }
        $rated = ($mem | Measure-Object Speed -Minimum).Minimum
        $running = ($mem | Measure-Object ConfiguredClockSpeed -Minimum).Minimum
        if ($rated -and $running -and $running -lt $rated) {
            if ($isLaptop) {
                Write-Check '情報' "メモリは ${running}MHz で動いています（メモリ自体は ${rated}MHz 対応）。ノート PC では CPU の上限で決まることが多く、正常な場合がほとんどです。"
            } else {
                Write-Check '注意' "メモリが ${running}MHz で動いています（メモリ自体は ${rated}MHz 対応）。" 'BIOS で XMP（Intel）/ EXPO（AMD）を有効にすると定格で動きます。CPU の上限が低いときはそのままで正常です。'
            }
        }
    }

    # ディスクの空き容量。少ないと更新や読み込みが遅くなる
    foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and "$($_.DriveType)" -eq 'Fixed' -and $_.Size -gt 0 })) {
        $freeGb = [math]::Round($v.SizeRemaining / 1GB, 1)
        $pct = [math]::Round(100.0 * $v.SizeRemaining / $v.Size)
        if ($pct -lt 10) {
            Write-Check '注意' "$($v.DriveLetter): ドライブの空きが少なめです（${freeGb}GB、${pct}%）。" '要らないファイルやゲームを消すか、設定 → システム → ストレージ → 一時ファイル で空けてください。'
        } else {
            Write-Check 'OK' "$($v.DriveLetter): ドライブの空き: ${freeGb}GB (${pct}%)"
        }
    }
}

# ③ 診断だけ。起動・セキュリティに関わるので変えない
function Show-SafetyCheck {
    Write-Host ''
    Write-Host '■ 起動とセキュリティの確認（ツールは変えません）' -ForegroundColor Cyan

    if (Test-Admin) {
        $bcd = (cmd /c 'bcdedit /enum {current} 2>nul') -join "`n"
        $changed = @(foreach ($k in @('useplatformclock', 'useplatformtick', 'disabledynamictick', 'tscsyncpolicy')) {
            # No / Default は書かれていても既定と同じ動きなので注意しない
            if ($bcd -match "(?m)^$k\s+(\S+)" -and $Matches[1] -notmatch '^(No|Default)$') { "$k=$($Matches[1])" }
        })
        if ($changed.Count -gt 0) {
            Write-Check '注意' ("起動設定（タイマー）が既定から変わっています: {0}" -f ($changed -join ', ')) ('既定に戻すには管理者で: ' + (($changed | ForEach-Object { 'bcdedit /deletevalue ' + ($_ -split '=')[0] }) -join ' ; ') + '  のあと再起動')
        } else {
            Write-Check 'OK' '起動設定（タイマー）は既定のままです。'
        }
    } else {
        Write-Check '情報' '起動設定は管理者で実行すると確認できます。'
    }

    try {
        $m = Get-ProcessMitigation -System
        # Windows の既定で有効なものだけを見る。ほかは既定がオフなので OFF でも正常
        $defaultsOn = @('DEP.Enable', 'ASLR.BottomUp', 'ASLR.HighEntropy', 'CFG.Enable', 'SEHOP.Enable', 'Heap.TerminateOnError')
        $off = @(foreach ($d in $defaultsOn) {
            $cat, $prop = $d -split '\.'
            if ("$($m.$cat.$prop)" -eq 'OFF') { $d }
        })
        if ($off.Count -gt 0) {
            Write-Check '注意' ("攻撃の緩和策がオフになっています: {0}" -f ($off -join ', ')) 'Windows セキュリティ → アプリとブラウザー コントロール → Exploit Protection の設定 → システム設定 で各項目を「既定で有効」に戻し、再起動'
        } else {
            Write-Check 'OK' '攻撃の緩和策は既定のままです。'
        }
    } catch {
        Write-Check '情報' '攻撃の緩和策は確認できませんでした。'
    }

    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    if ($dg) {
        if ($dg.VirtualizationBasedSecurityStatus -eq 2) {
            Write-Check 'OK' '仮想化ベースのセキュリティ (VBS) は動いています。'
        } else {
            Write-Check '情報' 'VBS は動いていません。ゲームには有利ですが、守りは弱くなります。'
        }
        # 2 = メモリ整合性 (HVCI)
        if (@($dg.SecurityServicesRunning) -contains 2) {
            Write-Check '情報' 'メモリ整合性はオンです。Microsoft は、一部の構成ではゲーム性能が下がることがあるとしています。' '気になるときだけ、ゲーム中に Windows セキュリティ → デバイス セキュリティ → コア分離 でオフにし、終わったら戻してください。'
        } else {
            Write-Check '情報' 'メモリ整合性はオフです。ゲームには有利ですが、守りは弱くなります。' '戻すなら Windows セキュリティ → デバイス セキュリティ → コア分離 → メモリ整合性'
        }
    }
    if (Test-Admin) {
        $vmp = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue
        if ($vmp -and "$($vmp.State)" -eq 'Enabled') {
            Write-Check '情報' '仮想マシン プラットフォーム (VMP) が有効です。WSL や Android アプリを使わないなら、一部の構成でゲームが軽くなることがあります。' 'Windows の機能の有効化または無効化 から外せます（使っている機能が動かなくなるので注意）。'
        }
    }

    # 全画面最適化を全体で切る設定（チューニングツールがよく入れる）。効果は賛否があるので表示だけ
    $gcs = 'HKCU:\System\GameConfigStore'
    if ((Get-RegValue $gcs 'GameDVR_HonorUserFSEBehaviorMode') -eq 1 -and (Get-RegValue $gcs 'GameDVR_FSEBehavior') -eq 2) {
        Write-Check '情報' '全画面最適化を全体で無効にする設定が入っています（チューニングツールが入れたものと見られます）。' '効果は賛否が分かれるので、ツールは変えません。特定のゲームだけ戻したいときは、その exe のプロパティ → 互換性 で設定できます。'
    }

    if ((Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' 'DisableAntiSpyware') -eq 1) {
        Write-Check '注意' 'ポリシーで Microsoft Defender が止められています。' '管理者で: Remove-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name DisableAntiSpyware'
    }
    $mp = $null
    try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { }
    $av = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue | ForEach-Object { $_.displayName })
    if ($mp -and $mp.RealTimeProtectionEnabled) {
        Write-Check 'OK' 'Microsoft Defender のリアルタイム保護はオンです。'
    } elseif (@($av | Where-Object { $_ -notmatch 'Defender' }).Count -gt 0) {
        Write-Check 'OK' ("ほかのウイルス対策が入っています: {0}" -f ($av -join ', '))
    } else {
        Write-Check '注意' 'リアルタイムのウイルス対策が確認できません。' 'Windows セキュリティ → ウイルスと脅威の防止 で確認してください。'
    }

    $lua = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA'
    $consent = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorAdmin'
    if ($lua -eq 0 -or $consent -eq 0) {
        Write-Check '注意' 'ユーザー アカウント制御 (UAC) が確認なしになっています。' 'スタートで「UAC」と検索 → ユーザー アカウント制御設定の変更 → 上から 2 番目（既定）'
    } else {
        Write-Check 'OK' 'ユーザー アカウント制御 (UAC) は有効です。'
    }

    $fwOff = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue | Where-Object { -not $_.Enabled } | ForEach-Object { $_.Name })
    if ((Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile' 'EnableFirewall') -eq 0) { $fwOff += 'Standard(ポリシー)' }
    if ($fwOff.Count -gt 0) {
        Write-Check '注意' ("ファイアウォールがオフ: {0}" -f ($fwOff -join ', ')) 'Windows セキュリティ → ファイアウォールとネットワーク保護 でオンにしてください。'
    } else {
        Write-Check 'OK' 'ファイアウォールはオンです。'
    }

    if ((Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableSmartScreen') -eq 0) {
        Write-Check '注意' 'ポリシーで SmartScreen が止められています。' '管理者で: Remove-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name EnableSmartScreen'
    }

    $unknownNet = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\010103000F0000F0010000000F0000F0C967A3643C3AD745950DA7859209176EF5B87C875FA20DF21951640E807D7C24'
    if ((Get-RegValue $unknownNet 'Category') -eq 1) {
        Write-Check '注意' '知らないネットワーク（外の Wi-Fi など）がプライベート扱いになっています。' "管理者で: Remove-ItemProperty `"$unknownNet`" -Name Category"
    }

    $rdpTcp = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
    if ((Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections') -eq 0 -and (Get-RegValue $rdpTcp 'UserAuthentication') -eq 0) {
        $edition = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'EditionID'
        if ($edition -match '^Core') {
            # Home は接続を受ける機能が無い。Pro に上げたときに効いてしまう
            Write-Check '情報' 'リモート デスクトップがネットワーク レベル認証なしの設定です（Home では受け付けないので今は実害なし）。' 'Pro にしたら、設定 → システム → リモート デスクトップ を確認してください。'
        } else {
            Write-Check '注意' 'リモート デスクトップがネットワーク レベル認証なしで開いています。' '設定 → システム → リモート デスクトップ で、使わないならオフ、使うならネットワーク レベル認証をオンに'
        }
    }
}

function Invoke-Diagnose {
    Show-Adapters
    $state = @(Get-State)
    Write-Host '■ 設定の比較' -ForegroundColor Cyan
    Show-Plan $state
    $n = @($state | Where-Object { -not $_.Ok }).Count
    if ($n -eq 0) {
        Write-Host 'すべておすすめどおりです。' -ForegroundColor Green
    } else {
        Write-Host "変更が必要なものが $n 件あります。メニューの 2 で入れられます。" -ForegroundColor Yellow
    }
    Show-Advice
    Show-SafetyCheck
}

function Invoke-Change($records, [string]$field) {
    $restart = @{}
    $failed = @{}
    foreach ($r in $records) {
        try {
            Set-Value $r $r.$field
            if ($r.Kind -in @('adv', 'pm', 'lso')) { $restart[$r.Guid] = $true }
        } catch {
            $failed[$r.Id] = $_.Exception.Message
        }
    }
    foreach ($g in @($restart.Keys)) {
        $n = Resolve-AdapterName $g
        if (-not $n) { continue }
        Write-Host "アダプターを再起動しています: $n（数秒ネットが切れます）"
        try { Restart-NetAdapter -Name $n -Confirm:$false } catch { Write-Host "  再起動に失敗: $($_.Exception.Message)" -ForegroundColor Red }
    }
    if ($restart.Count -gt 0) { Start-Sleep -Seconds 5 }

    Write-Host ''
    Write-Host '■ 結果' -ForegroundColor Cyan
    foreach ($r in $records) {
        $line = "{0} / {1}: {2} → {3}" -f $r.Target, $r.Label, (Format-Val $r.Old), (Format-Val $r.New)
        if ($field -eq 'Old') { $line = "{0} / {1}: {2} に戻す" -f $r.Target, $r.Label, (Format-Val $r.Old) }
        if ($failed.ContainsKey($r.Id)) {
            Write-Host "  [失敗] $line  理由: $($failed[$r.Id])" -ForegroundColor Red
            continue
        }
        $after = $null
        try { $after = Get-Value $r } catch { }
        if ("$after" -eq "$($r.$field)") {
            Write-Host "  [OK]   $line" -ForegroundColor Green
        } else {
            Write-Host "  [未反映] $line  今の値: $(Format-Val $after)" -ForegroundColor Yellow
        }
    }
    if (@($records | Where-Object { $_.Kind -eq 'regraw' }).Count -gt 0) {
        Write-Host ''
        Write-Host 'GPU の設定は PC を再起動すると反映されます。' -ForegroundColor Yellow
    }
}

function Invoke-Apply {
    Show-Adapters
    $state = @(Get-State)
    Write-Host '■ 設定の比較' -ForegroundColor Cyan
    Show-Plan $state
    $todo = @($state | Where-Object { -not $_.Ok })
    if ($todo.Count -eq 0) {
        Write-Host 'すべておすすめどおりです。変更はありません。' -ForegroundColor Green
        return
    }
    Write-Host "$($todo.Count) 件を変更します。途中でネットが数秒切れるので、ゲームや通話は終えてから進めてください。" -ForegroundColor Yellow
    if ((Read-Host '進めますか？ (y/n)') -ne 'y') { Write-Host '中止しました。'; return }

    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    $file = Join-Path $BackupDir ('backup_{0}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $records = foreach ($s in $todo) {
        [pscustomobject]@{
            Id = $s.Id; Kind = $s.Kind; Label = $s.Label; Target = $s.Target; Guid = $s.Guid; Key = $s.Key
            Path = $s.Path; Name = $s.Name; RegType = $s.RegType; Scheme = $s.Scheme; Sub = $s.Sub; Setting = $s.Setting; Prop = $s.Prop
            Old = $s.Current; New = $s.Want
        }
    }
    # 変更より先に保存する
    ConvertTo-Json -InputObject @($records) -Depth 3 | Set-Content -Path $file -Encoding UTF8
    Write-Host "変更前の値を保存しました: $file"
    Invoke-Change @($records) 'New'
}

function Invoke-Restore {
    $file = $BackupFile
    if (-not $file) {
        $files = @(Get-ChildItem -Path $BackupDir -Filter 'backup_*.json' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 10)
        if ($files.Count -eq 0) { Write-Host '保存された値がありません。'; return }
        for ($i = 0; $i -lt $files.Count; $i++) { Write-Host ("  {0}. {1}" -f ($i + 1), $files[$i].Name) }
        $c = Read-Host '戻したい番号 (Enter で 1 = いちばん新しいもの)'
        if (-not $c) { $c = '1' }
        $ci = 0
        if (-not [int]::TryParse($c, [ref]$ci) -or $ci -lt 1 -or $ci -gt $files.Count) { Write-Host '番号が違います。'; return }
        $file = $files[$ci - 1].FullName
    }
    $raw = Get-Content -Path $file -Raw -Encoding UTF8 | ConvertFrom-Json
    $records = @($raw | ForEach-Object { $_ })
    Write-Host "$file の値に戻します:"
    foreach ($r in $records) { Write-Host ("  {0} / {1}: {2}" -f $r.Target, $r.Label, (Format-Val $r.Old)) }
    if ((Read-Host '進めますか？ (y/n)') -ne 'y') { Write-Host '中止しました。'; return }
    [array]::Reverse($records)
    Invoke-Change $records 'Old'
}

function Measure-Target([string]$label, [string]$address, [int]$count) {
    Write-Host "$label ($address) を $count 回測っています..."
    $ping = New-Object System.Net.NetworkInformation.Ping
    $rtts = New-Object System.Collections.Generic.List[double]
    $lost = 0
    for ($i = 0; $i -lt $count; $i++) {
        try {
            $r = $ping.Send($address, 1000)
            if ($r.Status -eq 'Success') { $rtts.Add([double]$r.RoundtripTime) } else { $lost++ }
        } catch { $lost++ }
        Start-Sleep -Milliseconds 100
    }
    $avg = $null; $min = $null; $max = $null; $jit = $null
    if ($rtts.Count -gt 0) {
        $m = $rtts | Measure-Object -Average -Minimum -Maximum
        $avg = [math]::Round($m.Average, 1); $min = $m.Minimum; $max = $m.Maximum
        $diffs = for ($i = 1; $i -lt $rtts.Count; $i++) { [math]::Abs($rtts[$i] - $rtts[$i - 1]) }
        if ($diffs) { $jit = [math]::Round((@($diffs) | Measure-Object -Average).Average, 1) } else { $jit = 0 }
    }
    [pscustomobject]@{
        相手 = $label; アドレス = $address; 平均ms = $avg; 最小ms = $min; 最大ms = $max
        ゆらぎms = $jit; ロス率 = ('{0:0.0}%' -f (100.0 * $lost / $count)); LostRate = (100.0 * $lost / $count)
    }
}

function Invoke-Measure {
    $count = 100
    $targets = @()
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric | Select-Object -First 1
    if ($route -and $route.NextHop -and $route.NextHop -ne '0.0.0.0') { $targets += , @('ルーター', $route.NextHop) }
    $targets += , @('インターネット', '1.1.1.1')

    $results = foreach ($t in $targets) { Measure-Target $t[0] $t[1] $count }
    Write-Host ''
    $text = $results | Select-Object 相手, アドレス, 平均ms, 最小ms, 最大ms, ゆらぎms, ロス率 |
        Format-Table -AutoSize | Out-String -Width 200
    Write-Host $text

    $when = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $via = if ($route) { $route.InterfaceAlias } else { '?' }
    Add-Content -Path $MeasureLog -Encoding UTF8 -Value ("==== $when  経路: $via" + "`r`n" + $text.Trim())
    Write-Host "結果を $MeasureLog に追記しました（設定の前後で比べられます）。"

    # 目安（厳密な基準ではない）。ロールバック方式の対戦では、平均の速さより揺れとロスが効く
    $gw = $results | Where-Object { $_.相手 -eq 'ルーター' }
    $net = $results | Where-Object { $_.相手 -eq 'インターネット' }
    Write-Host ''
    Write-Host '■ 目安' -ForegroundColor Cyan
    if ($gw -and ($gw.LostRate -gt 0 -or $gw.ゆらぎms -ge 3)) {
        Write-Host '  ルーターまでで既に揺れています。Wi-Fi や LAN ケーブルなど家の中が原因の可能性が高いです。' -ForegroundColor Yellow
    } elseif ($net -and ($net.LostRate -gt 0 -or $net.ゆらぎms -ge 5)) {
        Write-Host '  家の中は安定していて、インターネット側で揺れています。回線の混雑や、ルーターの先が原因の可能性があります。' -ForegroundColor Yellow
        Write-Host '  格闘ゲームでは、少しのロスや揺れでも巻き戻りやカクつきが増えます。時間を変えて測り直すと、混む時間帯かどうか分かります。'
    } else {
        Write-Host '  大きな問題は見えません。'
    }
    Write-Host '  ここで測れるのは自分の側だけです。対戦のラグは、相手の回線や距離でも決まります。'
    Write-Host '  ダウンロード中や家族の動画再生中だけ遅いなら、ルーター側の詰まり (Bufferbloat) の可能性があります。'
    Write-Host '  確認: https://www.waveform.com/tools/bufferbloat'
}

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host "=== 格闘ゲーム向け PC 設定チェック (FGNetCheck $AppVersion) ===" -ForegroundColor Cyan
        Write-Host '  1. 診断する（設定・手作業の案内・セキュリティの確認。何も変えません）'
        Write-Host '  2. おすすめ設定を入れる（変更前の値を保存します）'
        Write-Host '  3. 元に戻す（保存した値に戻します）'
        Write-Host '  4. 通信を測る（ping、約 20 秒）'
        Write-Host '  Q. 終わる'
        $c = Read-Host '番号を入れて Enter'
        try {
            switch ("$c".Trim()) {
                '1' { Invoke-Diagnose }
                '2' { Invoke-Apply }
                '3' { Invoke-Restore }
                '4' { Invoke-Measure }
                'q' { return }
                default { Write-Host '1〜4 か Q を入れてください。' }
            }
        } catch {
            Write-Host "エラー: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

switch ($Mode) {
    'Menu'     { Show-Menu }
    'Diagnose' { Invoke-Diagnose }
    'Apply'    { Invoke-Apply }
    'Restore'  { Invoke-Restore }
    'Measure'  { Invoke-Measure }
}
