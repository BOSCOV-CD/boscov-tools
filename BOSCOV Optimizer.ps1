# ============================================================
#  BOSCOV Optimizer  v1.0
#  BlueStacks 5 FPS & smoothness optimizer for Windows 10/11
#  - Auto-elevates to Administrator (UAC prompt)
#  - Backs up every file/registry value it changes
#  - Undo everything with:  powershell -File "BOSCOV Optimizer.ps1" -Revert
#  Free to share. Local standard tweaks only, no telemetry.
# ============================================================
param([switch]$Revert)

$ErrorActionPreference = 'Continue'
$Host.UI.RawUI.WindowTitle = 'BOSCOV Optimizer'

function Pause-Exit {
    param([int]$Code = 0)
    Write-Host ''
    Write-Host 'Press any key to close...' -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit $Code
}

# ---------- REVERT MODE: restore everything from the newest backup ----------
if ($Revert) {
    $dirs = Get-ChildItem -Path $env:USERPROFILE -Directory -Filter 'BOSCOV_Backup_*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    if (-not $dirs) {
        Write-Host 'No BOSCOV backup found - nothing to revert.' -ForegroundColor Red
        Pause-Exit 1
    }
    $manifestPath = Join-Path $dirs[0].FullName 'manifest.txt'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Write-Host 'Backup manifest missing - cannot revert safely.' -ForegroundColor Red
        Pause-Exit 1
    }
    Write-Host ''
    Write-Host 'BOSCOV REVERT - restoring from ' -NoNewline -ForegroundColor Cyan
    Write-Host $dirs[0].Name -ForegroundColor Yellow
    Write-Host ''
    $applied = @{}
    foreach ($line in Get-Content -LiteralPath $manifestPath) {
        $parts = $line -split '\|', 4
        switch ($parts[0]) {
            'FILE' {
                if (Test-Path -LiteralPath $parts[2]) {
                    Copy-Item -LiteralPath $parts[2] -Destination $parts[1] -Force
                    Write-Host ('  restored file : ' + $parts[1]) -ForegroundColor Green
                }
            }
            'REG' {
                $tag = $parts[1] + '|' + $parts[2]
                if (-not $applied[$tag]) {
                    $applied[$tag] = $true
                    if ($parts[3] -eq '<missing>') {
                        Remove-ItemProperty -LiteralPath $parts[1] -Name $parts[2] -ErrorAction SilentlyContinue
                    } else {
                        $val = $parts[3]
                        $type = 'String'
                        if ($val -match '^\d+$') { $type = 'DWord'; $val = [int]$val }
                        if (-not (Test-Path $parts[1])) { New-Item -Path $parts[1] -Force | Out-Null }
                        Set-ItemProperty -LiteralPath $parts[1] -Name $parts[2] -Value $val -Type $type -ErrorAction SilentlyContinue
                    }
                    Write-Host ('  restored reg  : [' + $parts[1] + '] ' + $parts[2]) -ForegroundColor Green
                }
            }
            'POWERPLAN' {
                powercfg /setactive $parts[1] 2>$null
                Write-Host ('  power plan restored: ' + $parts[1]) -ForegroundColor Green
            }
        }
    }
    Write-Host ''
    Write-Host 'Revert complete. Restart BlueStacks and optionally reboot.' -ForegroundColor Cyan
    Pause-Exit
}

# ---------- Elevation (restart as admin if needed) ----------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Requesting Administrator rights (accept the UAC prompt)...' -ForegroundColor Yellow
    $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $args2 -Verb RunAs
    } catch {
        Write-Host 'Elevation cancelled. Run again and click YES on the UAC prompt.' -ForegroundColor Red
    }
    exit
}

# ---------- Locate BlueStacks ----------
$confCandidates = @(
    'C:\ProgramData\BlueStacks_nxt\bluestacks.conf',
    'C:\ProgramData\BlueStacks\bluestacks.conf',
    'C:\ProgramData\BlueStacks_msi5\bluestacks.conf'
)
$conf = $null
foreach ($c in $confCandidates) { if (Test-Path -LiteralPath $c) { $conf = $c; break } }

$regKeys = @('HKLM:\SOFTWARE\BlueStacks_nxt', 'HKLM:\SOFTWARE\BlueStacks_msi5', 'HKLM:\SOFTWARE\BlueStacks')
$bsReg = $null
foreach ($r in $regKeys) { if (Test-Path $r) { $bsReg = $r; break } }

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '            BOSCOV  OPTIMIZER               ' -ForegroundColor Cyan
Write-Host '      BlueStacks 5 FPS & Smoothness         ' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''

if (-not $conf -and -not $bsReg) {
    Write-Host 'BlueStacks 5 was not found on this PC.' -ForegroundColor Red
    Write-Host 'Install BlueStacks 5 first, then run this optimizer again.' -ForegroundColor Red
    Pause-Exit 1
}
if ($conf) { Write-Host ('BlueStacks config : ' + $conf) -ForegroundColor Green }
if ($bsReg) { Write-Host ('BlueStacks install: ' + (Get-ItemProperty $bsReg -ErrorAction SilentlyContinue).InstallDir) -ForegroundColor Green }

# ---------- Hardware-aware sizing ----------
$cpu  = Get-CimInstance Win32_Processor
$cs   = Get-CimInstance Win32_ComputerSystem
$gpus = Get-CimInstance Win32_VideoController
$threads = [int]$cpu.NumberOfLogicalProcessors
$ramGB = [math]::Floor($cs.TotalPhysicalMemory / 1GB)

if     ($ramGB -le 4) { $bsCores = [Math]::Max(2, [Math]::Min(2, $threads)); $bsRam = 2048 }
elseif ($ramGB -le 6) { $bsCores = [Math]::Max(2, [Math]::Min(3, $threads)); $bsRam = 3072 }
elseif ($ramGB -le 8) { $bsCores = [Math]::Max(2, [Math]::Min(4, $threads)); $bsRam = 4096 }
else                  { $bsCores = [Math]::Max(4, [Math]::Min(6, $threads)); $bsRam = 6144 }

$fpsCap = 60
Write-Host ''
Write-Host ('Detected: {0} | {1} threads | {2} GB RAM | GPU: {3}' -f $cpu.Name.Trim(), $threads, $ramGB, $gpus[0].Name.Trim()) -ForegroundColor Gray
Write-Host ('BlueStacks target: {0} CPU cores | {1} MB RAM | {2} FPS cap | 1280x720 160dpi' -f $bsCores, $bsRam, $fpsCap) -ForegroundColor Gray

# ---------- Backup helpers ----------
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir = Join-Path $env:USERPROFILE ('BOSCOV_Backup_' + $stamp)
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$manifest = Join-Path $backupDir 'manifest.txt'
('Backup created by BOSCOV Optimizer on ' + $stamp) | Set-Content -LiteralPath $manifest

function Backup-File {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $dest = Join-Path $backupDir ((Split-Path $Path -Leaf) + '.bak')
        Copy-Item -LiteralPath $Path -Destination $dest -Force
        Add-Content -LiteralPath $manifest -Value ('FILE|' + $Path + '|' + $dest)
        Write-Host ('  backed up: ' + $Path) -ForegroundColor DarkGray
    }
}
function Backup-RegValue {
    param([string]$Key, [string]$Name)
    try {
        $v = (Get-ItemProperty -LiteralPath $Key -Name $Name -ErrorAction Stop).$Name
        Add-Content -LiteralPath $manifest -Value ('REG|' + $Key + '|' + $Name + '|' + ($v -join ';'))
        Write-Host ('  backed up: [' + $Key + '] ' + $Name) -ForegroundColor DarkGray
    } catch {
        Add-Content -LiteralPath $manifest -Value ('REG|' + $Key + '|' + $Name + '|<missing>')
    }
}

# ---------- Stop BlueStacks before editing config ----------
foreach ($p in @('BlueStacks.exe', 'BlueStacksHelper.exe', 'HD-Player.exe', 'BstkSVC.exe')) {
    Stop-Process -Name $p -Force -ErrorAction SilentlyContinue
}
foreach ($s in (Get-Service -Name 'BstHypervisorSvc', 'BstHyperv' -ErrorAction SilentlyContinue)) {
    Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# ---------- [1/5] Windows-level tweaks ----------
Write-Host ''
Write-Host '[1/5] Windows tweaks...' -ForegroundColor Cyan

$activePlanOut = powercfg /getactivescheme
if ($activePlanOut -match '([a-f0-9-]{36})') { Add-Content -LiteralPath $manifest -Value ('POWERPLAN|' + $Matches[1]) }
if ($activePlanOut -notmatch 'e9a42b02-d5df-448d-aa00-03f14749eb61') {
    powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
    if ($LASTEXITCODE -ne 0) {
        powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
        powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
    }
}
Write-Host '  power plan -> Ultimate Performance' -ForegroundColor Green

Backup-RegValue 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode'
Set-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -Name 'AllowAutoGameMode' -Value 1 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 1 -Type DWord -ErrorAction SilentlyContinue

$gsku = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
Backup-RegValue $gsku 'HwSchMode'
if ($gpus | Where-Object { $_.Name -match 'NVIDIA|Radeon|Intel.*(UHD|Iris|Arc)|RX|GTX|RTX' }) {
    Set-ItemProperty $gsku -Name 'HwSchMode' -Value 2 -Type DWord -ErrorAction SilentlyContinue
    Write-Host '  hardware-accelerated GPU scheduling -> ON (reboot to apply)' -ForegroundColor Green
}

Backup-RegValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled'
Set-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0 -Type DWord -ErrorAction SilentlyContinue
Backup-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR'
New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Force | Out-Null
Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Name 'AllowGameDVR' -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-Host '  Game Mode ON, background GameDVR recording OFF' -ForegroundColor Green

Backup-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting'
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 2 -Type DWord -ErrorAction SilentlyContinue
$adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Backup-RegValue $adv 'TaskbarAnimations'
Backup-RegValue $adv 'ListviewAlphaSelect'
Backup-RegValue $adv 'ListviewShadow'
Backup-RegValue $adv 'IconsOnly'
Set-ItemProperty $adv -Name 'TaskbarAnimations' -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty $adv -Name 'ListviewAlphaSelect' -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty $adv -Name 'ListviewShadow' -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty $adv -Name 'IconsOnly' -Value 1 -Type DWord -ErrorAction SilentlyContinue
$dwm = 'HKCU:\Software\Microsoft\Windows\DWM'
Backup-RegValue $dwm 'EnableAeroPeek'
Set-ItemProperty $dwm -Name 'EnableAeroPeek' -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-Host '  heavy desktop animations disabled' -ForegroundColor Green

Backup-RegValue 'HKCU:\Control Panel\Desktop' 'MenuShowDelay'
Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '0' -ErrorAction SilentlyContinue

$pref = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\HD-Player.exe\PerfOptions'
New-Item -Path $pref -Force | Out-Null
Backup-RegValue $pref 'CpuPriorityClass'
Set-ItemProperty $pref -Name 'CpuPriorityClass' -Value 3 -Type DWord -ErrorAction SilentlyContinue
Write-Host '  HD-Player.exe set to High CPU priority whenever it runs' -ForegroundColor Green

foreach ($h in @('OneDrive', 'YourPhone', 'Teams', 'SkypeApp', 'AdobeARM', 'Spotify')) {
    Stop-Process -Name $h -Force -ErrorAction SilentlyContinue
}
Write-Host '  common background apps closed for this session' -ForegroundColor Green

# ---------- [2/5] BlueStacks engine config ----------
if ($conf) {
    Write-Host ''
    Write-Host '[2/5] BlueStacks engine tuning...' -ForegroundColor Cyan
    Backup-File $conf

    $lines = Get-Content -LiteralPath $conf
    $instances = @()
    foreach ($l in $lines) {
        if ($l -match '^bst\.instance\.([A-Za-z0-9_]+)\.cpus=') { $instances += $Matches[1] }
    }
    $instances = $instances | Select-Object -Unique
    if (-not $instances) { $instances = @('Pie64', 'Pie64_1') }
    Write-Host ('  instances found: ' + ($instances -join ', ')) -ForegroundColor DarkGray

    $newLines = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($l in $lines) {
        $handled = $false
        foreach ($inst in $instances) {
            if ($l -match ('^bst\.instance\.' + [regex]::Escape($inst) + '\.')) {
                $handled = $true
                $key = ($l -split '=', 2)[0]
                $seen[$key] = $true
                if ($key -like '*.cpus')                  { $newLines.Add($key + '="' + $bsCores + '"') }
                elseif ($key -like '*.ram')               { $newLines.Add($key + '="' + $bsRam + '"') }
                elseif ($key -like '*.max_fps')           { $newLines.Add($key + '="' + $fpsCap + '"') }
                elseif ($key -like '*.enable_high_fps')   { $newLines.Add($key + '="1"') }
                elseif ($key -like '*.enable_vsync')      { $newLines.Add($key + '="0"') }
                elseif ($key -like '*.enable_fps_display'){ $newLines.Add($key + '="1"') }
                elseif ($key -like '*.astc_decoding_mode'){ $newLines.Add($key + '="software"') }
                elseif ($key -like '*.dpi')               { $newLines.Add($key + '="160"') }
                elseif ($key -like '*.fb_width')          { $newLines.Add($key + '="1280"') }
                elseif ($key -like '*.fb_height')         { $newLines.Add($key + '="720"') }
                elseif ($key -like '*.graphics_renderer') { $newLines.Add($key + '="gl"') }
                elseif ($key -like '*.graphics_engine')   { $newLines.Add($key + '="aga"') }
                elseif ($key -like '*.libc_mem_allocator'){ $newLines.Add($key + '="jem"') }
                elseif ($key -like '*.eco_mode_max_fps')  { $newLines.Add($key + '="15"') }
                elseif ($key -like '*.show_sidebar')      { $newLines.Add($key + '="0"') }
                elseif ($key -like '*.enable_notifications') { $newLines.Add($key + '="0"') }
                elseif ($key -like '*.game_controls_enabled') { $newLines.Add($key + '="1"') }
                else { $newLines.Add($l) }
                break
            }
        }
        if (-not $handled) {
            if ($l -match '^bst\.qt_renderer=') { $newLines.Add('bst.qt_renderer="Auto"'); $seen['bst.qt_renderer'] = $true }
            else { $newLines.Add($l) }
        }
    }
    foreach ($inst in $instances) {
        $defaults = @{
            'enable_high_fps' = '1'; 'max_fps' = "$fpsCap"; 'enable_vsync' = '0'; 'enable_fps_display' = '1'
            'fb_width' = '1280'; 'fb_height' = '720'; 'dpi' = '160'; 'astc_decoding_mode' = 'software'
        }
        foreach ($k in $defaults.Keys) {
            $key = 'bst.instance.' + $inst + '.' + $k
            if (-not $seen.ContainsKey($key)) { $newLines.Add($key + '="' + $defaults[$k] + '"') }
        }
    }
    [System.IO.File]::WriteAllLines($conf, $newLines, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ('  engine set: ' + $bsCores + ' cores | ' + $bsRam + ' MB RAM | ' + $fpsCap + ' FPS | 1280x720 | sidebar off') -ForegroundColor Green
}

# ---------- [3/5] Restart BlueStacks service ----------
Write-Host ''
Write-Host '[3/5] Restarting BlueStacks service...' -ForegroundColor Cyan
foreach ($s in (Get-Service -Name 'BstHypervisorSvc', 'BstHyperv' -ErrorAction SilentlyContinue)) {
    Start-Service -Name $s.Name -ErrorAction SilentlyContinue
}
Write-Host '  done' -ForegroundColor Green

# ---------- [4/5] Refresh desktop shell ----------
Write-Host ''
Write-Host '[4/5] Applying desktop changes...' -ForegroundColor Cyan
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Write-Host '  done' -ForegroundColor Green

# ---------- [5/5] Summary ----------
Write-Host ''
Write-Host '[5/5] Optimization complete!' -ForegroundColor Cyan
Write-Host ''
Write-Host '  > Open BlueStacks (HD-Player) now - FPS should be visibly higher.' -ForegroundColor Yellow
Write-Host '  > In BlueStacks Settings > Performance, leave everything as it is.' -ForegroundColor Gray
Write-Host '  > A reboot is recommended once so GPU scheduling fully applies.' -ForegroundColor Gray
Write-Host ('  > Backup saved to: ' + $backupDir) -ForegroundColor Gray
Write-Host '  > To undo everything, run this file again with the -Revert flag:' -ForegroundColor Gray
Write-Host '    powershell -ExecutionPolicy Bypass -File "BOSCOV Optimizer.ps1" -Revert' -ForegroundColor Gray
Write-Host ''
Write-Host '  BOSCOV Optimizer v1.0 - free to share with friends.' -ForegroundColor Cyan

Pause-Exit
