# ============================================================
#  BOSCOV FPS INJECTOR  v1.0  (SUPER EDITION)
#  Auto FPS booster for BlueStacks 5 on Windows 10/11.
#  Detects your CPU, RAM and GPU, then injects the highest
#  stable FPS settings into BlueStacks all by itself.
#  - 100% automatic: no menus, no guessing
#  - Auto-elevates to Administrator (UAC prompt)
#  - Backs up every file/value it changes
#  - Undo everything with:  powershell -File "BOSCOV FPS Injector.ps1" -Revert
#  Free to share. Local standard tweaks only, no telemetry.
# ============================================================
param([switch]$Revert)

$ErrorActionPreference = 'Continue'
$Host.UI.RawUI.WindowTitle = 'BOSCOV FPS Injector'

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
    Write-Host 'Revert complete. Restart BlueStacks.' -ForegroundColor Cyan
    Pause-Exit
}

# ---------- Elevation (restart as admin if needed) ----------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Requesting Administrator rights (accept the UAC prompt)...' -ForegroundColor Yellow
    $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
    if ($Revert) { $args2 += '-Revert' }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $args2 -Verb RunAs
    } catch {
        Write-Host 'Elevation cancelled. Run again and click YES on the UAC prompt.' -ForegroundColor Red
    }
    exit
}

Write-Host ''
Write-Host '  ============================================================' -ForegroundColor Cyan
Write-Host '     B O S C O V   F P S   I N J E C T O R   -   SUPER' -ForegroundColor Cyan
Write-Host '     Auto-injects max FPS into BlueStacks. No settings needed.' -ForegroundColor Gray
Write-Host '  ============================================================' -ForegroundColor Cyan

# ---------- Locate BlueStacks config automatically ----------
$conf = $null
$candidates = @(
    (Join-Path $env:ProgramData 'BlueStacks_nxt\bluestacks.conf'),
    (Join-Path ${env:ProgramFiles} 'BlueStacks_nxt\bluestacks.conf'),
    (Join-Path ${env:ProgramFiles(x86)} 'BlueStacks_nxt\bluestacks.conf'),
    (Join-Path $env:ProgramData 'BlueStacks\bluestacks.conf')
)
foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { $conf = $c; break } }
if (-not $conf) {
    $hits = Get-ChildItem -Path $env:ProgramData -Recurse -Filter 'bluestacks.conf' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($hits) { $conf = $hits.FullName }
}
if (-not $conf) {
    try {
        $rk = Get-ItemProperty 'HKLM:\SOFTWARE\BlueStacks_nxt' -ErrorAction Stop
        if ($rk.InstallDir) {
            $p = Join-Path $rk.InstallDir 'bluestacks.conf'
            if (Test-Path -LiteralPath $p) { $conf = $p }
        }
    } catch {}
}
if ($conf) {
    Write-Host ''
    Write-Host ('  BlueStacks config found: ' + $conf) -ForegroundColor Green
} else {
    Write-Host ''
    Write-Host '  BlueStacks 5 config not found on this PC.' -ForegroundColor Red
    Write-Host '  Install BlueStacks 5 first, then run the Injector again.' -ForegroundColor Red
    Pause-Exit 1
}

# ---------- AUTO-DETECT hardware and compute SUPER settings ----------
Write-Host ''
Write-Host '[1/4] Detecting your hardware...' -ForegroundColor Cyan

$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$logicalCores = [int]($cpu.NumberOfLogicalProcessors)
$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)

$gpus = Get-CimInstance Win32_VideoController
$hasDedicated = $false
foreach ($g in $gpus) {
    if ($g.Name -match 'GTX|RTX|Radeon RX|Radeon (R|HD) (7|8|9)|Arc|MX') { $hasDedicated = $true }
}
$monitorHz = 60
foreach ($g in $gpus) {
    if ($g.CurrentRefreshRate -and $g.CurrentRefreshRate -gt $monitorHz) { $monitorHz = [int]$g.CurrentRefreshRate }
}

# Cores: give BlueStacks half the CPU (min 2, max 6), never all of them
$bsCores = [math]::Floor($logicalCores / 2)
if ($bsCores -lt 2) { $bsCores = 2 }
if ($bsCores -gt 6) { $bsCores = 6 }

# RAM: scale with total RAM
if     ($ramGB -ge 32) { $bsRam = 8192 }
elseif ($ramGB -ge 16) { $bsRam = 4096 }
elseif ($ramGB -ge 8)  { $bsRam = 3072 }
else                   { $bsRam = 2048 }

# FPS: SUPER mode injects the highest practical target
if ($hasDedicated) { $fpsCap = 240 } else { $fpsCap = 120 }

# Resolution: high-end hardware gets 1080p, everything else 720p
if ($ramGB -ge 16 -and $hasDedicated) { $fbW = '1600'; $fbH = '900' }
else                                  { $fbW = '1280'; $fbH = '720' }

$gpuName = ($gpus | Select-Object -First 1).Name
Write-Host ('  CPU ........ ' + $cpu.Name.Trim() + ' (' + $logicalCores + ' threads)') -ForegroundColor Gray
Write-Host ('  RAM ........ ' + $ramGB + ' GB') -ForegroundColor Gray
Write-Host ('  GPU ........ ' + $gpuName + ($(if ($hasDedicated) { '  [dedicated - SUPER tier]' } else { '  [integrated]' }))) -ForegroundColor Gray
Write-Host ('  Monitor .... ' + $monitorHz + ' Hz') -ForegroundColor Gray
Write-Host ''
Write-Host ('  Injecting: ' + $bsCores + ' cores | ' + $bsRam + ' MB RAM | ' + $fpsCap + ' FPS | ' + $fbW + 'x' + $fbH) -ForegroundColor Green

# ---------- Backup helpers ----------
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir = Join-Path $env:USERPROFILE ('BOSCOV_Backup_' + $stamp)
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$manifest = Join-Path $backupDir 'manifest.txt'
('Backup created by BOSCOV FPS Injector on ' + $stamp) | Set-Content -LiteralPath $manifest

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

# ---------- [2/4] Inject FPS settings into every BlueStacks instance ----------
Write-Host ''
Write-Host '[2/4] Injecting SUPER FPS settings...' -ForegroundColor Cyan
Backup-File $conf

$lines = Get-Content -LiteralPath $conf
$instances = @()
foreach ($l in $lines) {
    if ($l -match '^bst\.instance\.([A-Za-z0-9_]+)\.cpus=') { $instances += $Matches[1] }
}
$instances = $instances | Select-Object -Unique
if (-not $instances) { $instances = @('Pie64') }
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
            if     ($key -like '*.cpus')                { $newLines.Add($key + '="' + $bsCores + '"') }
            elseif ($key -like '*.ram')                 { $newLines.Add($key + '="' + $bsRam + '"') }
            elseif ($key -like '*.max_fps')             { $newLines.Add($key + '="' + $fpsCap + '"') }
            elseif ($key -like '*.enable_high_fps')     { $newLines.Add($key + '="1"') }
            elseif ($key -like '*.enable_vsync')        { $newLines.Add($key + '="0"') }
            elseif ($key -like '*.enable_fps_display')  { $newLines.Add($key + '="1"') }
            elseif ($key -like '*.astc_decoding_mode')  { $newLines.Add($key + '="software"') }
            elseif ($key -like '*.dpi')                 { $newLines.Add($key + '="160"') }
            elseif ($key -like '*.fb_width')            { $newLines.Add($key + '="' + $fbW + '"') }
            elseif ($key -like '*.fb_height')           { $newLines.Add($key + '="' + $fbH + '"') }
            elseif ($key -like '*.graphics_renderer')   { $newLines.Add($key + '="gl"') }
            elseif ($key -like '*.graphics_engine')     { $newLines.Add($key + '="aga"') }
            elseif ($key -like '*.libc_mem_allocator')  { $newLines.Add($key + '="jem"') }
            elseif ($key -like '*.eco_mode_max_fps')    { $newLines.Add($key + '="15"') }
            elseif ($key -like '*.show_sidebar')        { $newLines.Add($key + '="0"') }
            elseif ($key -like '*.enable_notifications'){ $newLines.Add($key + '="0"') }
            elseif ($key -like '*.game_controls_enabled'){ $newLines.Add($key + '="1"') }
            else { $newLines.Add($l) }
            break
        }
    }
    if (-not $handled) { $newLines.Add($l) }
}
foreach ($inst in $instances) {
    $defaults = @{
        'enable_high_fps' = '1'; 'max_fps' = "$fpsCap"; 'enable_vsync' = '0'; 'enable_fps_display' = '1'
        'fb_width' = "$fbW"; 'fb_height' = "$fbH"; 'dpi' = '160'; 'astc_decoding_mode' = 'software'
        'graphics_renderer' = 'gl'; 'graphics_engine' = 'aga'; 'libc_mem_allocator' = 'jem'
    }
    foreach ($k in $defaults.Keys) {
        $key = 'bst.instance.' + $inst + '.' + $k
        if (-not $seen.ContainsKey($key)) { $newLines.Add($key + '="' + $defaults[$k] + '"') }
    }
}
[System.IO.File]::WriteAllLines($conf, $newLines, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('  injected: ' + $fpsCap + ' FPS cap | high-FPS ON | vsync OFF | renderer GL (AGA)') -ForegroundColor Green

# ---------- [3/4] Windows-level FPS helpers ----------
Write-Host ''
Write-Host '[3/4] Applying Windows FPS helpers...' -ForegroundColor Cyan

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

$pref = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\HD-Player.exe\PerfOptions'
New-Item -Path $pref -Force | Out-Null
Backup-RegValue $pref 'CpuPriorityClass'
Set-ItemProperty $pref -Name 'CpuPriorityClass' -Value 3 -Type DWord -ErrorAction SilentlyContinue
Write-Host '  HD-Player.exe set to High CPU priority whenever it runs' -ForegroundColor Green

Backup-RegValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled'
Set-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-Host '  background GameDVR recording OFF' -ForegroundColor Green

# ---------- [4/4] Restart BlueStacks service + summary ----------
Write-Host ''
Write-Host '[4/4] Restarting BlueStacks service...' -ForegroundColor Cyan
foreach ($s in (Get-Service -Name 'BstHypervisorSvc', 'BstHyperv' -ErrorAction SilentlyContinue)) {
    Start-Service -Name $s.Name -ErrorAction SilentlyContinue
}
Write-Host '  done' -ForegroundColor Green

Write-Host ''
Write-Host '  ==============================================' -ForegroundColor Cyan
Write-Host '   SUPER INJECTION COMPLETE!' -ForegroundColor Green
Write-Host '  ==============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host '  > Open BlueStacks (HD-Player) now and enable the FPS' -ForegroundColor Yellow
Write-Host ('    display (already ON) - you should see up to ' + $fpsCap + ' FPS.') -ForegroundColor Yellow
Write-Host '  > Leave BlueStacks Settings > Performance untouched -' -ForegroundColor Gray
Write-Host '    the Injector already set everything automatically.' -ForegroundColor Gray
Write-Host ('  > Backup saved to: ' + $backupDir) -ForegroundColor Gray
Write-Host '  > To undo everything, run this file again with the -Revert flag:' -ForegroundColor Gray
Write-Host '    powershell -ExecutionPolicy Bypass -File "BOSCOV FPS Injector.ps1" -Revert' -ForegroundColor Gray
Write-Host ''
Write-Host '  BOSCOV FPS Injector v1.0 SUPER - free to share with friends.' -ForegroundColor Cyan

Pause-Exit
