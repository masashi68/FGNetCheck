<#
FGNetCheck.ps1  格闘ゲーム向け PC 設定チェック

  1. 診断      今の設定とおすすめの差、手作業の案内、起動・セキュリティの確認を表示する（何も変えない）
  2. 適用      おすすめ設定を入れる。変更前の値を backup フォルダに保存する
  3. 元に戻す  保存した値に戻す
  4. 測定      ping で遅延・ゆらぎ・跳ね・ロスを測り、measure_log.txt に残す
               （短い測定・長い測定・負荷をかけた測定。P2P のつながりやすさも確かめる）

配布版は FGNetCheck.bat の 1 ファイル（build.ps1 がこのファイルを bat に埋め込む）。
bat から動くときは -Launcher に bat のパスが渡り、backup などは bat の隣にできる。
#>
param(
    [ValidateSet('Menu', 'Diagnose', 'Apply', 'Restore', 'Measure')]
    [string]$Mode = 'Menu',
    [string]$BackupFile,
    [string]$Launcher,
    # -Mode Measure のときの測り方。メニューから選んだときは画面で尋ねる
    [ValidateSet('Short', 'Long', 'Load')]
    [string]$Measure = 'Short'
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

# インターネットへ出るときに実際に使う経路。
# 優先順位は「ルートのメトリック + インターフェイスのメトリック」で決まるので、Windows に経路を引かせる
function Get-InternetRoute {
    $r = $null
    try {
        $r = @(Find-NetRoute -RemoteIPAddress '1.1.1.1' -ErrorAction Stop |
            Where-Object { $_.PSObject.Properties['NextHop'] }) | Select-Object -First 1
    } catch { }
    if (-not $r) {
        $r = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Sort-Object { [int]$_.RouteMetric + [int]$_.InterfaceMetric } | Select-Object -First 1
    }
    if (-not $r) { return $null }
    $a = Get-NetAdapter -InterfaceIndex $r.InterfaceIndex -IncludeHidden -ErrorAction SilentlyContinue | Select-Object -First 1
    # VPN・仮想スイッチ・テザリングなどは other
    $kind = 'other'
    if ($a -and -not $a.Virtual -and $a.NdisPhysicalMedium -eq 9) { $kind = 'wifi' }
    elseif ($a -and -not $a.Virtual -and $a.NdisPhysicalMedium -eq 14) { $kind = 'wired' }
    [pscustomobject]@{ Alias = "$($r.InterfaceAlias)"; Index = $r.InterfaceIndex; NextHop = "$($r.NextHop)"; Adapter = $a; Kind = $kind }
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
    $route = Get-InternetRoute
    if ($route) {
        Write-Host "  インターネットに使っているもの: $($route.Alias)"
        if ($route.Kind -eq 'wifi') {
            Write-Host '  注意: Wi-Fi でつないでいます。格闘ゲームのオンライン対戦では、揺れやロスが巻き戻りやカクつきになって出ます。有線 LAN にするのがいちばん効きます。' -ForegroundColor Yellow
        } elseif ($route.Kind -eq 'other') {
            Write-Host '  注意: 有線 LAN でも Wi-Fi でもないアダプター（VPN、仮想スイッチ、テザリングなど）を通っています。VPN を使っているなら、対戦のあいだは切ると遅延が減ります。' -ForegroundColor Yellow
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
    if (@($state | Where-Object { $_.Group -eq 'B' -and -not $_.Ok }).Count -gt 0) {
        Write-Host "※「$($GroupName['B'])」は TCP の設定です。対戦中の通信は多くのゲームで UDP なので、対戦の遅延は変わりません。"
        Write-Host '  ダウンロードやブラウザーなどの通信を、他のツールが変える前の状態に戻すための項目です。'
    }
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
    $route = Get-InternetRoute
    if ($route -and $route.Kind -eq 'wifi') {
        $sig = $null
        $wl = (cmd /c 'netsh wlan show interfaces') -join "`n"
        if ($wl -match '(\d{1,3})\s*%') { $sig = [int]$Matches[1] }
        if ($null -ne $sig -and $sig -lt 70) {
            Write-Check '注意' "Wi-Fi の電波が弱めです（$sig%）。" 'ルーターに近づく、5GHz / 6GHz を使う、有線 LAN にする、のどれかが効きます。'
        } elseif ($null -ne $sig) {
            Write-Check 'OK' "Wi-Fi の電波: $sig%"
        } else {
            # Windows 11 24H2 以降は、位置情報がオフだと netsh が Wi-Fi の情報を返さない
            Write-Check '情報' 'Wi-Fi の電波の強さを読めませんでした。' 'Windows 11 24H2 以降は、設定 → プライバシーとセキュリティ → 位置情報 がオフだと読めません。タスクバーの Wi-Fi アイコンの本数で確かめてください。'
        }
        Write-Check '情報' '数十秒おきに ping が跳ねるときは、Wi-Fi の周辺スキャンが原因のことがあります。' 'Wi-Fi ドライバーの更新と、ルーターのローミング・背景スキャンの設定を確認してください。'
    }

    # 有線のリンク速度と通信エラー。ケーブルや差し込み口の不良は、速度の低下やエラーとして出る
    foreach ($a in @(Get-TargetAdapters | Where-Object { $_.NdisPhysicalMedium -eq 14 -and "$($_.Status)" -eq 'Up' })) {
        $mbps = [math]::Round([double]$a.Speed / 1000000)
        if ($mbps -gt 0 -and $mbps -lt 1000) {
            Write-Check '注意' "$($a.Name) が ${mbps}Mbps でつながっています。" 'LAN ケーブル（Cat5e 以上か、傷んでいないか）と差し込み口を確かめてください。ルーターやハブが 100Mbps までの機種なら、このままで正常です。'
        } elseif ($mbps -ge 1000) {
            Write-Check 'OK' "$($a.Name) のリンク速度: $($a.LinkSpeed)"
        }
        $st = Get-NetAdapterStatistics -Name $a.Name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($st) {
            $err = [double]$st.ReceivedPacketErrors + [double]$st.OutboundPacketErrors
            $pk = [double]$st.ReceivedUnicastPackets + [double]$st.SentUnicastPackets
            if ($err -gt 0 -and $pk -gt 0 -and ($err / $pk) -ge 0.0001) {
                Write-Check '注意' "$($a.Name) で通信エラーが多めです（$err 件。アダプターが動き始めてからの合計）。" 'LAN ケーブルを替える、ルーターやハブの別の差し込み口を使う、のどちらかを試してください。'
            } elseif ($err -gt 0) {
                Write-Check '情報' "$($a.Name) で通信エラーが少しあります（$err 件。アダプターが動き始めてからの合計）。増え続けるなら LAN ケーブルを疑ってください。"
            }
        }
    }

    # ドライバーの既定と違うアダプター設定。省電力と LSO は上の表で扱うので除く
    $handled = @($AdvKeywords | ForEach-Object { $_.Key })
    foreach ($a in Get-TargetAdapters) {
        $changed = @(Get-NetAdapterAdvancedProperty -Name $a.Name -ErrorAction SilentlyContinue | Where-Object {
            $cur = "$(@($_.RegistryValue)[0])"
            $def = "$($_.DefaultRegistryValue)"
            $def -ne '' -and $cur -ne '' -and $cur -ne $def -and $_.RegistryKeyword -notin $handled -and $_.RegistryKeyword -notlike '*Lso*'
        })
        if ($changed.Count -gt 0) {
            $txt = ($changed | ForEach-Object { "{0}: {1}（既定 {2}）" -f $_.DisplayName, $_.DisplayValue, $_.DefaultDisplayValue }) -join ' / '
            Write-Check '情報' "$($a.Name) で、ドライバーの既定と違う設定: $txt" '変えた覚えがなければ、デバイス マネージャー → ネットワーク アダプター → プロパティ → 詳細設定 で既定に戻せます。PC メーカーが出荷時に変えていることもあります。'
        }
    }

    # 配信の最適化。3 = インターネット上の PC にも更新を配る。ポリシーがあればそちらが優先される
    $doMode = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode'
    if ($null -eq $doMode) {
        $doMode = Get-RegValue 'Registry::HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Settings' 'DownloadMode'
    }
    if ($doMode -eq 3) {
        Write-Check '情報' 'Windows Update の「配信の最適化」が、インターネット上の PC にも更新を配る設定です。配っているあいだは上りの帯域を使います。' '設定 → Windows Update → 詳細オプション → 配信の最適化 で「ローカル ネットワーク上のデバイス」を選ぶか、オフにしてください。'
    }

    Write-Check '情報' 'P2P で対戦するゲームでつながりにくい・相手が限られるときは、ルーター側の設定が原因のことがあります。' 'メニューの 4（通信を測る）で、NAT の型と二重ルーターを確かめられます。ルーターの UPnP を有効にするか、ゲームの案内に従ってポートを開けてください。'

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

# ---------------------------------------------------------------
# 通信を測る
# ---------------------------------------------------------------

# いつもの値（中央値）よりこれ以上遅れた回を「跳ね」と数える。60fps の 1 フレームは約 16.7ms
$SpikeMs = 17
# 負荷をかけた測定で使う、Cloudflare の速度測定用サーバー
$LoadHost = 'https://speed.cloudflare.com'

function Get-Percentile([double[]]$sorted, [double]$p) {
    if ($null -eq $sorted -or $sorted.Count -eq 0) { return $null }
    $i = [int][math]::Ceiling($p / 100.0 * $sorted.Count) - 1
    if ($i -lt 0) { $i = 0 }
    if ($i -ge $sorted.Count) { $i = $sorted.Count - 1 }
    return $sorted[$i]
}

function Get-MeasureTargets($route) {
    if ($route -and $route.NextHop -and $route.NextHop -ne '0.0.0.0' -and $route.NextHop -notmatch ':') {
        [pscustomobject]@{ Label = 'ルーター'; Address = $route.NextHop }
    }
    [pscustomobject]@{ Label = 'インターネット'; Address = '1.1.1.1' }
}

# 複数の相手を同じ瞬間に測る。跳ねやロスがどちら側で起きたかを、相手どうしで突き合わせられる。
# 戻り値の Rtt は相手ごとの往復時間 (ms) の並びで、返事が無かった回は -1
function Invoke-PingRun($targets, [int]$seconds, [string]$activity, [scriptblock]$stopWhen) {
    $targets = @($targets)
    $n = $targets.Count
    $pings = New-Object object[] $n
    $rtt = New-Object object[] $n
    for ($k = 0; $k -lt $n; $k++) {
        $pings[$k] = New-Object System.Net.NetworkInformation.Ping
        $rtt[$k] = New-Object System.Collections.Generic.List[double]
    }
    $at = New-Object System.Collections.Generic.List[double]
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $i = 0
    while ($sw.Elapsed.TotalSeconds -lt $seconds) {
        if ($stopWhen -and (& $stopWhen)) { break }
        $t0 = $sw.Elapsed.TotalMilliseconds
        $at.Add([math]::Round($t0 / 1000, 1))
        $tasks = New-Object object[] $n
        for ($k = 0; $k -lt $n; $k++) {
            try { $tasks[$k] = $pings[$k].SendPingAsync([string]$targets[$k].Address, 1000) } catch { $tasks[$k] = $null }
        }
        for ($k = 0; $k -lt $n; $k++) {
            $v = -1.0
            $t = $tasks[$k]
            if ($t) {
                try {
                    $t.Wait()
                    if ("$($t.Result.Status)" -eq 'Success') { $v = [double]$t.Result.RoundtripTime }
                } catch { }
            }
            $rtt[$k].Add($v)
        }
        $i++
        if ($activity -and ($i % 10) -eq 0) {
            $pct = [int][math]::Min(100, 100 * $sw.Elapsed.TotalSeconds / $seconds)
            Write-Progress -Activity $activity -Status ("{0} / {1} 秒" -f [int]$sw.Elapsed.TotalSeconds, $seconds) -PercentComplete $pct
        }
        # 1 秒に約 10 回
        $wait = 100 - ($sw.Elapsed.TotalMilliseconds - $t0)
        if ($wait -ge 1) { Start-Sleep -Milliseconds ([int]$wait) }
    }
    if ($activity) { Write-Progress -Activity $activity -Completed }
    foreach ($p in $pings) { $p.Dispose() }
    [pscustomobject]@{ Rtt = $rtt; At = $at; Seconds = $sw.Elapsed.TotalSeconds }
}

function Get-PingStats([string]$label, [string]$address, $rtts) {
    $all = @($rtts)
    $ok = @($all | Where-Object { $_ -ge 0 })
    $lost = $all.Count - $ok.Count
    $run = 0; $maxRun = 0
    foreach ($v in $all) {
        if ($v -lt 0) { $run++; if ($run -gt $maxRun) { $maxRun = $run } } else { $run = 0 }
    }
    $avg = $null; $med = $null; $p95 = $null; $p99 = $null; $max = $null; $jit = $null; $limit = $null; $spikes = 0
    if ($ok.Count -gt 0) {
        $sorted = [double[]]@($ok | Sort-Object)
        $avg = [math]::Round(($ok | Measure-Object -Average).Average, 1)
        $med = Get-Percentile $sorted 50
        $p95 = Get-Percentile $sorted 95
        $p99 = Get-Percentile $sorted 99
        $max = $sorted[$sorted.Count - 1]
        $sum = 0.0
        for ($i = 1; $i -lt $ok.Count; $i++) { $sum += [math]::Abs($ok[$i] - $ok[$i - 1]) }
        $jit = if ($ok.Count -gt 1) { [math]::Round($sum / ($ok.Count - 1), 1) } else { 0 }
        $limit = $med + $SpikeMs
        $spikes = @($ok | Where-Object { $_ -ge $limit }).Count
    }
    $lossRate = if ($all.Count -gt 0) { 100.0 * $lost / $all.Count } else { 0 }
    $spikeRate = if ($ok.Count -gt 0) { 100.0 * $spikes / $ok.Count } else { 0 }
    [pscustomobject]@{
        Label = $label; Address = $address; Count = $all.Count; Received = $ok.Count; Lost = $lost
        LossRate = $lossRate; MaxLossRun = $maxRun; Avg = $avg; Median = $med; P95 = $p95; P99 = $p99; Max = $max
        Jitter = $jit; Limit = $limit; Spikes = $spikes; SpikeRate = $spikeRate
    }
}

function Format-PingStats($stats) {
    $rows = foreach ($s in @($stats)) {
        [pscustomobject][ordered]@{
            相手 = $s.Label; アドレス = $s.Address; 回数 = $s.Count; 平均ms = $s.Avg; 中央ms = $s.Median
            '95%ms' = $s.P95; '99%ms' = $s.P99; 最大ms = $s.Max; ゆらぎms = $s.Jitter; 跳ね = $s.Spikes
            ロス率 = ('{0:0.0}%' -f $s.LossRate); 連続ロス = $s.MaxLossRun
        }
    }
    # -Property * を付けないと、表は 10 列までしか出ない
    ($rows | Format-Table -Property * -AutoSize | Out-String -Width 200).Trim()
}

# 跳ね・ロスが起きた回の番号
function Get-BadIndexes($rtts, $limit) {
    $all = @($rtts)
    for ($i = 0; $i -lt $all.Count; $i++) {
        if ($all[$i] -lt 0 -or ($null -ne $limit -and $all[$i] -ge $limit)) { $i }
    }
}

# 跳ね・ロスが起きた時刻（開始からの秒）。1 秒以内に続いたものは 1 回にまとめる
function Format-BadTimes($rtts, $limit, $at) {
    $times = @(Get-BadIndexes $rtts $limit | ForEach-Object { $at[$_] })
    if ($times.Count -eq 0) { return $null }
    $groups = New-Object System.Collections.Generic.List[double]
    $last = -100.0
    foreach ($t in $times) {
        if (($t - $last) -gt 1.0) { $groups.Add($t) }
        $last = $t
    }
    $shown = @($groups | Select-Object -First 15 | ForEach-Object { '{0:0}' -f $_ })
    $text = $shown -join ', '
    if ($groups.Count -gt 15) { $text += " ほか $($groups.Count - 15) 回" }
    return $text
}

# 測定のあいだに、このアダプターを流れた通信量を知るため
function Get-AdapterBytes([string]$name) {
    if (-not $name) { return $null }
    $s = Get-NetAdapterStatistics -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $s) { return $null }
    [pscustomobject]@{ Rx = [double]$s.ReceivedBytes; Tx = [double]$s.SentBytes }
}

function Get-Mbps([double]$bytes, [double]$seconds) {
    if ($seconds -le 0) { return 0 }
    [math]::Round($bytes * 8 / 1000000 / $seconds, 1)
}

# 目安（厳密な基準ではない）。ロールバック方式の対戦では、平均の速さより揺れ・跳ね・ロスが効く
function Get-MeasureVerdict($stats, $run) {
    $notes = New-Object System.Collections.Generic.List[string]
    $stats = @($stats)
    $gwAt = -1; $netAt = -1
    for ($k = 0; $k -lt $stats.Count; $k++) {
        if ($stats[$k].Label -eq 'ルーター') { $gwAt = $k }
        if ($stats[$k].Label -eq 'インターネット') { $netAt = $k }
    }
    $gw = if ($gwAt -ge 0) { $stats[$gwAt] } else { $null }
    $net = if ($netAt -ge 0) { $stats[$netAt] } else { $null }

    if ($net -and $net.Received -eq 0) {
        $notes.Add('注意: インターネット (1.1.1.1) から返事がありません。つながっていないか、ping が止められています。')
        return $notes
    }
    if ($gw -and $gw.Received -eq 0) {
        $notes.Add('情報: ルーターが ping に答えないので、家の中とインターネット側を分けて判定できません。')
        $gw = $null
    }
    $gwBad = $gw -and ($gw.LossRate -ge 0.2 -or $gw.Jitter -ge 3 -or $gw.SpikeRate -ge 0.5)
    $netBad = $net -and ($net.LossRate -ge 0.2 -or $net.Jitter -ge 5 -or $net.SpikeRate -ge 0.5)

    # インターネット側の跳ね・ロスのうち、同じ瞬間（前後 1 回を含む）にルーターでも起きていた割合
    $overlap = $null
    if ($gw -and $net) {
        $gwIdx = @{}
        foreach ($i in @(Get-BadIndexes $run.Rtt[$gwAt] $gw.Limit)) { $gwIdx[$i] = $true }
        $netIdx = @(Get-BadIndexes $run.Rtt[$netAt] $net.Limit)
        if ($netIdx.Count -gt 0) {
            $hit = @($netIdx | Where-Object { $gwIdx.ContainsKey($_) -or $gwIdx.ContainsKey($_ - 1) -or $gwIdx.ContainsKey($_ + 1) }).Count
            $overlap = $hit / $netIdx.Count
        }
    }

    if ($gwBad -and $netBad) {
        if ($null -eq $overlap -or $overlap -ge 0.5) {
            $notes.Add('注意: ルーターまでの区間で既に揺れていて、インターネット側の揺れと同じタイミングで起きています。Wi-Fi、LAN ケーブル、ルーターなど家の中が原因の可能性が高いです。')
        } else {
            $notes.Add('注意: ルーターとインターネットの両方で揺れていますが、起きたタイミングは重なっていません。インターネット側（回線の混雑や、ルーターの先）が原因の可能性があります。')
            $notes.Add('  ルーターは自分あての ping への返事を後回しにすることがあり、ルーターの揺れはそのせいかもしれません。')
        }
    } elseif ($gwBad) {
        $notes.Add('情報: ルーターあての ping だけが揺れていて、インターネット側は安定しています。ルーターは自分あての ping への返事を後回しにすることがあるので、通信そのものには問題がない可能性が高いです。')
    } elseif ($netBad) {
        $notes.Add('注意: 家の中は安定していて、インターネット側で揺れています。回線の混雑や、ルーターの先が原因の可能性があります。')
        $notes.Add('  格闘ゲームでは、少しのロスや跳ねでも巻き戻りやカクつきが増えます。時間を変えて測り直すと、混む時間帯かどうか分かります。')
    } else {
        $notes.Add('大きな問題は見えません。')
    }
    if ($net -and -not $netBad -and ($net.Spikes -gt 0 -or $net.Lost -gt 0)) {
        $notes.Add("  インターネット側で、跳ねが $($net.Spikes) 回、ロスが $($net.Lost) 回ありました。回数が少ないので、たまたまの可能性もあります。")
    }
    return $notes
}

# ---- 負荷をかけた測定 ----

# 別スレッドで動かす。$state.Stop が立つまで、ダウンロードまたはアップロードを繰り返す
$LoadWorker = {
    param($state, [int]$id, [string]$kind, [string]$url, [int]$repeat, [int]$size)
    $buf = New-Object byte[] 16384
    $total = 0.0
    for ($n = 0; $n -lt $repeat -and -not $state.Stop; $n++) {
        $req = $null
        try {
            $req = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($url)
            $req.Timeout = 8000
            $req.ReadWriteTimeout = 5000
            $req.UserAgent = 'FGNetCheck'
            if ($kind -eq 'up') {
                $req.Method = 'POST'
                $req.ContentType = 'application/octet-stream'
                $req.AllowWriteStreamBuffering = $false
                $req.ContentLength = $size
                $s = $req.GetRequestStream()
                $left = $size
                while ($left -gt 0 -and -not $state.Stop) {
                    $c = [math]::Min($left, $buf.Length)
                    $s.Write($buf, 0, $c)
                    $left -= $c
                    $total += $c
                    $state["bytes$id"] = $total
                }
                if ($state.Stop) { $req.Abort(); break }
                $s.Close()
                $req.GetResponse().Close()
            } else {
                $resp = $req.GetResponse()
                $s = $resp.GetResponseStream()
                while (-not $state.Stop) {
                    $c = $s.Read($buf, 0, $buf.Length)
                    if ($c -le 0) { break }
                    $total += $c
                    $state["bytes$id"] = $total
                }
                if ($state.Stop) { $req.Abort(); break }
                $resp.Close()
            }
        } catch {
            $state["err$id"] = 1 + [int]$state["err$id"]
            if ($req) { try { $req.Abort() } catch { } }
            Start-Sleep -Milliseconds 300
        }
    }
}

function Start-Load([string]$kind, [int]$streams, [int]$repeat, [int]$size) {
    $state = [hashtable]::Synchronized(@{ Stop = $false })
    $url = if ($kind -eq 'up') { "$LoadHost/__up" } else { "$LoadHost/__down?bytes=$size" }
    $workers = for ($w = 0; $w -lt $streams; $w++) {
        $ps = [powershell]::Create()
        [void]$ps.AddScript($LoadWorker.ToString()).AddArgument($state).AddArgument($w).AddArgument($kind).AddArgument($url).AddArgument($repeat).AddArgument($size)
        [pscustomobject]@{ Ps = $ps; Handle = $ps.BeginInvoke() }
    }
    [pscustomobject]@{ State = $state; Workers = @($workers); Streams = $streams }
}

function Get-LoadBytes($load) {
    $sum = 0.0
    for ($w = 0; $w -lt $load.Streams; $w++) { $sum += [double]$load.State["bytes$w"] }
    $sum
}

function Test-LoadDone($load) {
    @($load.Workers | Where-Object { -not $_.Handle.IsCompleted }).Count -eq 0
}

function Stop-Load($load) {
    $load.State.Stop = $true
    foreach ($w in $load.Workers) {
        try {
            if ($w.Handle.AsyncWaitHandle.WaitOne(6000)) { $w.Ps.Dispose() } else { [void]$w.Ps.BeginStop($null, $null) }
        } catch { }
    }
}

# 回線をわざと混ませて、そのときの ping を空いているときと比べる（Bufferbloat の実測）
function Invoke-LoadMeasure($targets, $log) {
    Write-Host ''
    Write-Host '負荷をかけた測定をします。' -ForegroundColor Cyan
    Write-Host '  ・ダウンロードとアップロードで回線をわざと混ませ、そのときの ping を比べます（約 40 秒）。'
    Write-Host '  ・通信量を使います（最大で 下り 約 300MB、上り 約 100MB。遅い回線ではもっと少なくなります）。'
    Write-Host '    テザリングや、通信量に上限のある回線では実行しないでください。'
    Write-Host '  ・Cloudflare の速度測定用サーバー (speed.cloudflare.com) に接続します。'
    Write-Host '  ・家族が使っている通信も、測っているあいだは遅くなります。'
    if ((Read-Host '進めますか？ (y/n)') -ne 'y') { Write-Host '中止しました。'; return $false }

    # Windows PowerShell 5.1 は、同じ相手への同時接続が 2 本までで、古い環境では TLS 1.2 が既定で使われない
    try {
        [System.Net.ServicePointManager]::DefaultConnectionLimit = 16
        [System.Net.ServicePointManager]::Expect100Continue = $false
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    } catch { }

    $netAt = @($targets).Count - 1
    Write-Host '1/3 何もしていないときを測っています（約 10 秒）...'
    $idleRun = Invoke-PingRun $targets 10 '何もしていないとき'
    $idle = Get-PingStats '負荷なし' '1.1.1.1' $idleRun.Rtt[$netAt]
    if ($idle.Received -eq 0) {
        Write-Host '  インターネット (1.1.1.1) から返事がないので、測れません。' -ForegroundColor Yellow
        return $false
    }

    $phases = @(
        @{ Kind = 'down'; Name = 'ダウンロード中'; Step = '2/3'; Repeat = 3; Size = 25000000 },
        @{ Kind = 'up';   Name = 'アップロード中'; Step = '3/3'; Repeat = 3; Size = 8000000 }
    )
    $rows = @($idle)
    $notes = New-Object System.Collections.Generic.List[string]
    foreach ($ph in $phases) {
        Write-Host ("{0} {1}を測っています（最大 約 14 秒）..." -f $ph.Step, $ph.Name)
        $load = Start-Load $ph.Kind 4 $ph.Repeat $ph.Size
        try {
            # 通信が速度に乗るまで少し待つ
            Start-Sleep -Milliseconds 1500
            $b0 = Get-LoadBytes $load
            $run = Invoke-PingRun $targets 12 $ph.Name { Test-LoadDone $load }
            $b1 = Get-LoadBytes $load
        } finally {
            Stop-Load $load
        }
        $mbps = Get-Mbps ($b1 - $b0) $run.Seconds
        $st = Get-PingStats $ph.Name '1.1.1.1' $run.Rtt[$netAt]
        $rows += $st
        $cap = 4.0 * $ph.Repeat * $ph.Size
        if ($st.Count -lt 20 -and $b1 -ge 0.9 * $cap) {
            $notes.Add("情報: $($ph.Name): 用意した通信量をすぐに送り終えたため、判定できるだけの回数を測れませんでした。回線が十分に速いときに起きます。")
            continue
        }
        if ($mbps -lt 0.5 -or $st.Count -lt 20) {
            $notes.Add("情報: $($ph.Name): 負荷を十分にかけられませんでした（測定用のサーバーに接続できないか、断られました）。この項目は判定できません。")
            continue
        }
        $inc = [math]::Round($st.Median - $idle.Median, 1)
        $inc95 = [math]::Round($st.P95 - $idle.P95, 1)
        $head = "$($ph.Name)（約 ${mbps}Mbps）: ping の中央値が $($idle.Median) → $($st.Median)ms、95% の値が $($idle.P95) → $($st.P95)ms"
        if ($st.Lost -gt $idle.Lost) { $head += "。ロスも $($st.Lost) 回" }
        if ($inc -ge 30 -or $inc95 -ge 60) {
            $notes.Add("注意: $head。回線が混むと大きく遅れます（Bufferbloat）。")
        } elseif ($inc -ge 5 -or $inc95 -ge 20) {
            $notes.Add("情報: $head。回線が混むと少し遅れます。")
        } else {
            $notes.Add("OK: $head。回線が混んでも、ほとんど遅れません。")
        }
    }

    $text = Format-PingStats $rows
    Write-Host ''
    Write-Host $text
    Write-Host ''
    Write-Host '■ 目安' -ForegroundColor Cyan
    foreach ($n in $notes) {
        $color = if ($n -like '注意*') { 'Yellow' } elseif ($n -like 'OK*') { 'Green' } else { 'Gray' }
        Write-Host "  $n" -ForegroundColor $color
    }
    if (@($notes | Where-Object { $_ -like '*回線が混むと*' }).Count -gt 0) {
        Write-Host '  対策: ルーターに QoS や SQM（fq_codel、CAKE など）の機能があれば有効にしてください。'
        Write-Host '        無ければ、対戦のあいだは他の機器や PC のダウンロード・アップロード（クラウドの同期、動画の投稿、ゲームの更新）を止めてください。'
    }
    $log.Add($text)
    foreach ($n in $notes) { $log.Add($n) }
    return $true
}

# ---- P2P 対戦のつながりやすさ ----

# STUN (RFC 5389) で、外から見た自分の IP アドレスとポートを尋ねる
function Get-StunMapping($udp, [string]$hostName, [int]$port) {
    try {
        $ip = [System.Net.Dns]::GetHostAddresses($hostName) |
            Where-Object { "$($_.AddressFamily)" -eq 'InterNetwork' } | Select-Object -First 1
        if (-not $ip) { return $null }
        $req = New-Object byte[] 20
        $req[1] = 1                                                      # Binding Request。属性なし
        $req[4] = 0x21; $req[5] = 0x12; $req[6] = 0xA4; $req[7] = 0x42   # magic cookie
        $tid = New-Object byte[] 12
        (New-Object System.Random).NextBytes($tid)
        [Array]::Copy($tid, 0, $req, 8, 12)
        $ep = New-Object System.Net.IPEndPoint $ip, $port
        for ($try = 0; $try -lt 2; $try++) {
            [void]$udp.Send($req, $req.Length, $ep)
            # 前の問い合わせへの遅れた返事が混ざることがあるので、番号が合うものを探す
            for ($r = 0; $r -lt 3; $r++) {
                $res = $null
                try {
                    $from = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any), 0
                    $res = $udp.Receive([ref]$from)
                } catch { break }
                $m = ConvertFrom-StunResponse $res $tid
                if ($m) { return $m }
            }
        }
    } catch { }
    return $null
}

function ConvertFrom-StunResponse([byte[]]$res, [byte[]]$tid) {
    if ($null -eq $res -or $res.Length -lt 20) { return $null }
    if ($res[0] -ne 1 -or $res[1] -ne 1) { return $null }               # Binding Success Response
    for ($i = 0; $i -lt 12; $i++) { if ($res[8 + $i] -ne $tid[$i]) { return $null } }
    $end = [math]::Min($res.Length, 20 + ($res[2] * 256 + $res[3]))
    $pos = 20
    $plain = $null
    while ($pos + 4 -le $end) {
        $type = $res[$pos] * 256 + $res[$pos + 1]
        $len = $res[$pos + 2] * 256 + $res[$pos + 3]
        $ok = ($pos + 4 + $len -le $end) -and $len -ge 8 -and $res[$pos + 5] -eq 1   # IPv4
        if ($ok -and $type -eq 0x0020) {
            # XOR-MAPPED-ADDRESS。magic cookie と XOR されている
            $p = ($res[$pos + 6] * 256 + $res[$pos + 7]) -bxor 0x2112
            $a = '{0}.{1}.{2}.{3}' -f ($res[$pos + 8] -bxor 0x21), ($res[$pos + 9] -bxor 0x12), ($res[$pos + 10] -bxor 0xA4), ($res[$pos + 11] -bxor 0x42)
            return [pscustomobject]@{ Address = $a; Port = [int]$p }
        }
        if ($ok -and $type -eq 0x0001) {
            $plain = [pscustomobject]@{
                Address = ('{0}.{1}.{2}.{3}' -f $res[$pos + 8], $res[$pos + 9], $res[$pos + 10], $res[$pos + 11])
                Port = [int]($res[$pos + 6] * 256 + $res[$pos + 7])
            }
        }
        $pos += 4 + $len + ((4 - ($len % 4)) % 4)
    }
    return $plain
}

function Get-AddressKind([string]$address) {
    $o = @($address -split '\.' | ForEach-Object { [int]$_ })
    if ($o.Count -ne 4) { return 'other' }
    if ($o[0] -eq 10 -or ($o[0] -eq 172 -and $o[1] -ge 16 -and $o[1] -le 31) -or ($o[0] -eq 192 -and $o[1] -eq 168)) { return 'private' }
    if ($o[0] -eq 100 -and $o[1] -ge 64 -and $o[1] -le 127) { return 'shared' }   # 100.64.0.0/10 (CGNAT)
    return 'public'
}

# 1.1.1.1 へ向かう経路の、ttl 番目の機器のアドレス
function Get-HopAddress([int]$ttl) {
    $ping = New-Object System.Net.NetworkInformation.Ping
    try {
        $opt = New-Object System.Net.NetworkInformation.PingOptions $ttl, $true
        for ($try = 0; $try -lt 2; $try++) {
            try {
                $r = $ping.Send('1.1.1.1', 1000, (New-Object byte[] 32), $opt)
                if ("$($r.Status)" -in @('TtlExpired', 'Success') -and $r.Address) { return "$($r.Address)" }
            } catch { }
        }
    } finally { $ping.Dispose() }
    return $null
}

function New-Note([string]$level, [string]$text, [string]$fix) {
    [pscustomobject]@{ Level = $level; Text = $text; Fix = $fix }
}

function Get-NatReport {
    $out = New-Object System.Collections.Generic.List[object]
    $a = $null; $b = $null
    $udp = $null
    try {
        $udp = New-Object System.Net.Sockets.UdpClient ([System.Net.Sockets.AddressFamily]::InterNetwork)
        $udp.Client.ReceiveTimeout = 1500
        # 同じソケット（同じ内側のポート）から 2 つの相手に尋ね、外側のポートが同じかを見る
        $a = Get-StunMapping $udp 'stun.l.google.com' 19302
        $b = Get-StunMapping $udp 'stun.cloudflare.com' 3478
    } catch { } finally { if ($udp) { $udp.Close() } }

    if ($a -and $b) {
        if ($a.Address -eq $b.Address -and $a.Port -eq $b.Port) {
            $out.Add((New-Note 'OK' '相手が変わっても、外から見たポートが変わらない型の NAT です。P2P の対戦でつながりやすい型です。'))
        } else {
            $out.Add((New-Note '注意' "相手ごとに、外から見たアドレスやポートが変わる型の NAT（対称 NAT）です（$($a.Address):$($a.Port) と $($b.Address):$($b.Port)）。P2P の対戦で、つながらない相手が出たり、中継サーバー経由になって遅延が増えたりします。" `
                'ルーターが 2 台重なっているなら、1 台をブリッジ（アクセスポイント）モードにしてください。集合住宅の共有回線、モバイル回線、VPN ではこの型になりやすく、その場合は PC 側では直せません。'))
        }
    } elseif ($a -or $b) {
        $out.Add((New-Note '情報' '確認用のサーバーの片方からしか返事がなく、NAT の型は判定できませんでした。'))
    } else {
        $out.Add((New-Note '情報' 'NAT の型は確認できませんでした（UDP が外へ出られないか、確認用のサーバーに届きません）。'))
    }

    $hop1 = Get-HopAddress 1
    $hop2 = Get-HopAddress 2
    if ($hop1 -and $hop2 -and (Get-AddressKind $hop1) -eq 'private') {
        $kind2 = Get-AddressKind $hop2
        if ($kind2 -eq 'private') {
            $out.Add((New-Note '情報' "ルーター ($hop1) の先にも、プライベート アドレスの機器 ($hop2) があります。ルーターが 2 台重なっている（二重ルーター）か、プロバイダーの網の中の機器です。" `
                'ONU やホームゲートウェイにもルーター機能があるなら、どちらか 1 台だけをルーターにすると、P2P の対戦がつながりやすくなります。つながりにくさを感じていなければ、そのままで構いません。'))
        } elseif ($kind2 -eq 'shared') {
            $out.Add((New-Note '情報' "ルーターの先が、プロバイダー側でアドレスを共有する区間 ($hop2) です（CGNAT）。ポートを開ける設定はできません。"))
        }
    }
    $out
}

function Invoke-Measure([string]$kind) {
    if (-not $kind) {
        Write-Host ''
        Write-Host '  1. 短い測定（約 20 秒）'
        Write-Host '  2. 長い測定（約 3 分。たまに起きる跳ねを見つけます。対戦と同じ環境で測るのに向きます）'
        Write-Host '  3. 負荷をかけた測定（約 40 秒。回線が混んだときの遅れを測ります。通信量を使います）'
        $c = "$(Read-Host '番号 (Enter で 1)')".Trim()
        $kind = switch ($c) { '' { 'Short' } '1' { 'Short' } '2' { 'Long' } '3' { 'Load' } default { $null } }
        if (-not $kind) { Write-Host '1〜3 を入れてください。'; return }
    }
    $route = Get-InternetRoute
    $targets = @(Get-MeasureTargets $route)
    $via = if ($route) { $route.Alias } else { '?' }
    $kindName = switch ($kind) { 'Long' { '長い測定' } 'Load' { '負荷をかけた測定' } default { '短い測定' } }
    $log = New-Object System.Collections.Generic.List[string]

    if ($kind -eq 'Load') {
        if (-not (Invoke-LoadMeasure $targets $log)) { return }
    } else {
        $seconds = if ($kind -eq 'Long') { 180 } else { 20 }
        $names = (@($targets) | ForEach-Object { "$($_.Label) ($($_.Address))" }) -join ' と '
        Write-Host "$names を同時に、約 $seconds 秒測っています..."
        $before = Get-AdapterBytes $via
        $run = Invoke-PingRun $targets $seconds '通信を測っています'
        $after = Get-AdapterBytes $via
        $stats = @(for ($k = 0; $k -lt $targets.Count; $k++) { Get-PingStats $targets[$k].Label $targets[$k].Address $run.Rtt[$k] })

        $text = Format-PingStats $stats
        Write-Host ''
        Write-Host $text
        Write-Host "  跳ね = いつもの値（中央値）より 1 フレーム（約 ${SpikeMs}ms）以上遅れた回数。95%ms = 100 回のうち 95 回はこの値以下。"
        $log.Add($text)

        for ($k = 0; $k -lt $targets.Count; $k++) {
            # 1 回も返事が無い相手は、時刻を並べても意味がない
            $times = if ($stats[$k].Received -gt 0) { Format-BadTimes $run.Rtt[$k] $stats[$k].Limit $run.At } else { $null }
            if ($times) {
                $line = "$($targets[$k].Label)で跳ね・ロスが起きた時刻（開始からの秒）: $times"
                Write-Host "  $line"
                $log.Add($line)
            }
        }

        Write-Host ''
        Write-Host '■ 目安' -ForegroundColor Cyan
        foreach ($n in @(Get-MeasureVerdict $stats $run)) {
            $color = if ($n -like '注意*') { 'Yellow' } else { 'Gray' }
            Write-Host "  $n" -ForegroundColor $color
            $log.Add($n)
        }
        if ($kind -eq 'Long') {
            Write-Host '  跳ねがほぼ同じ間隔で並んでいるなら、Wi-Fi の周辺スキャンなど、決まった間隔で動く処理が原因の可能性があります。'
        }
        if ($before -and $after) {
            $rx = Get-Mbps ($after.Rx - $before.Rx) $run.Seconds
            $tx = Get-Mbps ($after.Tx - $before.Tx) $run.Seconds
            if ($rx -ge 1 -or $tx -ge 0.5) {
                $line = "情報: 測っているあいだ、この PC でほかの通信が流れていました（下り 約 ${rx}Mbps、上り 約 ${tx}Mbps）。結果が悪く出ることがあります。"
                Write-Host "  $line"
                $log.Add($line)
            }
        }
        Write-Host '  ここで測れるのは自分の側だけです。対戦のラグは、相手の回線や距離でも決まります。'
        Write-Host '  ダウンロード中や家族の動画再生中だけ遅いなら、ルーター側の詰まり (Bufferbloat) の可能性があります。4 → 3 の「負荷をかけた測定」で確かめられます。'
    }

    Write-Host ''
    Write-Host '■ P2P 対戦のつながりやすさ（目安）' -ForegroundColor Cyan
    foreach ($n in @(Get-NatReport)) {
        Write-Check $n.Level $n.Text $n.Fix
        $log.Add("[$($n.Level)] $($n.Text)")
    }
    Write-Host '  IPv4 over IPv6（v6プラス、transix など）の回線では、使えるポートが限られたり、ポートを開けられなかったりします。'

    $when = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $MeasureLog -Encoding UTF8 -Value ("==== $when  経路: $via  $kindName" + "`r`n" + ($log -join "`r`n"))
    Write-Host ''
    Write-Host "結果を $MeasureLog に追記しました（設定の前後で比べられます）。"
}

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host "=== 格闘ゲーム向け PC 設定チェック (FGNetCheck $AppVersion) ===" -ForegroundColor Cyan
        Write-Host '  1. 診断する（設定・手作業の案内・セキュリティの確認。何も変えません）'
        Write-Host '  2. おすすめ設定を入れる（変更前の値を保存します）'
        Write-Host '  3. 元に戻す（保存した値に戻します）'
        Write-Host '  4. 通信を測る（短い測定・長い測定・負荷をかけた測定）'
        Write-Host '  Q. 終わる'
        $c = Read-Host '番号を入れて Enter'
        try {
            switch ("$c".Trim()) {
                '1' { Invoke-Diagnose }
                '2' { Invoke-Apply }
                '3' { Invoke-Restore }
                '4' { Invoke-Measure '' }
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
    'Measure'  { Invoke-Measure $Measure }
}
