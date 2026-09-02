# ============================================================
#  BOSCOV Boost  v1.0
#  RAM / startup / background / telemetry booster for Windows 10/11
#  - Auto-elevates to Administrator (UAC prompt)
#  - Backs up every value it changes
#  - Undo everything with:  powershell -File "BOSCOV Boost.ps1" -Revert
#  Free to share. Local standard tweaks only, no telemetry.
# ============================================================
param([switch]$Revert)

$ErrorActionPreference = 'Continue'
$Host.UI.RawUI.WindowTitle = 'BOSCOV Boost'

function Pause-Exit {
    param([int]$Code = 0)
    Write-Host ''
    Write-Host 'Press any key to close...' -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit $Code
}

# ---------- auto-elevate ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process -FilePath 'powershell' -Verb RunAs -ArgumentList ("-ExecutionPolicy Bypass -File `"" + $PSCommandPath + "`"")
    exit
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir = Join-Path $env:USERPROFILE ('BOSCOV_Boost_Backup_' + $stamp)
$manifestPath = Join-Path $backupDir 'manifest.txt'
$manifest = New-Object System.Collections.Generic.List[string]

function Backup-RegValue {
    param([string]$Key, [string]$Name)
    $v = Get-ItemProperty -LiteralPath $Key -Name $Name -ErrorAction SilentlyContinue
    if ($null -ne $v) { $manifest.Add(('REG|' + $Key + '|' + $Name + '|' + $v.$Name)) }
    else { $manifest.Add(('REG|' + $Key + '|' + $Name + '|<missing>')) }
}

# ---------- REVERT MODE ----------
if ($Revert) {
    $dirs = Get-ChildItem -Path $env:USERPROFILE -Directory -Filter 'BOSCOV_Boost_Backup_*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    if (-not $dirs) {
        Write-Host 'No BOSCOV Boost backup found - nothing to revert.' -ForegroundColor Red
        Pause-Exit 1
    }
    $mp = Join-Path $dirs[0].FullName 'manifest.txt'
    if (-not (Test-Path -LiteralPath $mp)) {
        Write-Host 'Backup manifest missing - cannot revert safely.' -ForegroundColor Red
        Pause-Exit 1
    }
    Write-Host ''
    Write-Host 'BOSCOV BOOST REVERT - restoring from ' -NoNewline -ForegroundColor Cyan
    Write-Host $dirs[0].Name -ForegroundColor Yellow
    Write-Host ''
    foreach ($line in Get-Content -LiteralPath $mp) {
        $parts = $line -split '\|', 4
        switch ($parts[0]) {
            'REG' {
                if ($parts[3] -eq '<missing>') {
                    Remove-ItemProperty -LiteralPath $parts[1] -Name $parts[2] -ErrorAction SilentlyContinue
                } else {
                    $val = $parts[3]; $type = 'String'
                    if ($val -match '^\d+$') { $type = 'DWord'; $val = [int]$val }
                    if (-not (Test-Path $parts[1])) { New-Item -Path $parts[1] -Force | Out-Null }
                    Set-ItemProperty -LiteralPath $parts[1] -Name $parts[2] -Value $val -Type $type -ErrorAction SilentlyContinue
                }
                Write-Host ('  restored reg   : [' + $parts[1] + '] ' + $parts[2]) -ForegroundColor Green
            }
            'START' {
                $bytes = for ($i = 0; $i -lt $parts[3].Length; $i += 2) { [Convert]::ToByte($parts[3].Substring($i, 2), 16) }
                Set-ItemProperty -LiteralPath $parts[1] -Name $parts[2] -Value ([byte[]]$bytes) -ErrorAction SilentlyContinue
                Write-Host ('  re-enabled app : ' + $parts[2]) -ForegroundColor Green
            }
            'SVC' {
                Set-Service -Name $parts[1] -StartupType $parts[2] -ErrorAction SilentlyContinue
                Write-Host ('  restored service : ' + $parts[1] + ' -> ' + $parts[2]) -ForegroundColor Green
            }
        }
    }
    Write-Host ''
    Write-Host 'Revert complete. Restart your PC to fully re-enable everything.' -ForegroundColor Cyan
    Pause-Exit
}

# ---------- MAIN MODE ----------
New-Item -Path $backupDir -ItemType Directory -Force | Out-Null

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '   BOSCOV BOOST  v1.0' -ForegroundColor Cyan
Write-Host '   RAM / Startup / Background Booster' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host ('  PC: ' + $env:COMPUTERNAME + '  |  RAM: ' + [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1) + ' GB') -ForegroundColor DarkGray
Write-Host ''

# ---------- [1/6] Disable startup apps ----------
Write-Host '[1/6] Disabling startup apps...' -ForegroundColor Cyan
$startKeys = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
)
$disabledCount = 0
foreach ($k in $startKeys) {
    if (-not (Test-Path $k)) { continue }
    $props = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
    if (-not $props) { continue }
    foreach ($p in $props.PSObject.Properties) {
        if ($p.Name -in @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) { continue }
        $b = $p.Value -as [byte[]]
        if (-not $b -or $b.Count -lt 1) { continue }
        if (($b[0] -band 0x02) -eq 0) { continue }   # already disabled
        $manifest.Add(('START|' + $k + '|' + $p.Name + '|' + (($b | ForEach-Object { $_.ToString('X2') }) -join '')))
        $newBytes = $b.Clone()
        $newBytes[0] = $b[0] -band 0xFD   # clear enabled bit -> disabled
        Set-ItemProperty -LiteralPath $k -Name $p.Name -Value ([byte[]]$newBytes) -ErrorAction SilentlyContinue
        $disabledCount++
        Write-Host ('  disabled: ' + $p.Name) -ForegroundColor Yellow
    }
}
if ($disabledCount -eq 0) { Write-Host '  no enabled startup apps found (already clean)' -ForegroundColor DarkGray }
Write-Host ('  done - ' + $disabledCount + ' startup app(s) disabled') -ForegroundColor Green

# ---------- [2/6] Background apps off ----------
Write-Host ''
Write-Host '[2/6] Turning off background apps...' -ForegroundColor Cyan
$bak = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'
Backup-RegValue $bak 'GlobalUserDisabled'
Set-ItemProperty -LiteralPath $bak -Name 'GlobalUserDisabled' -Value 1 -Type DWord -ErrorAction SilentlyContinue
$bp = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
Backup-RegValue $bp 'LetAppsRunInBackground'
if (-not (Test-Path $bp)) { New-Item -Path $bp -Force | Out-Null }
Set-ItemProperty -LiteralPath $bp -Name 'LetAppsRunInBackground' -Value 2 -Type DWord -ErrorAction SilentlyContinue
Write-Host '  store apps can no longer run in the background' -ForegroundColor Green

# ---------- [3/6] Telemetry services ----------
Write-Host ''
Write-Host '[3/6] Disabling telemetry services...' -ForegroundColor Cyan
foreach ($svc in @('DiagTrack', 'dmwappushservice')) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        $startMode = (Get-CimInstance Win32_Service -Filter ("Name='" + $svc + "'")).StartMode
        $manifest.Add(('SVC|' + $svc + '|' + $startMode))
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host ('  ' + $svc + ' -> disabled') -ForegroundColor Green
    } else {
        Write-Host ('  ' + $svc + ' not present (skip)') -ForegroundColor DarkGray
    }
}

# ---------- [4/6] SysMain decision ----------
Write-Host ''
Write-Host '[4/6] Checking disk type for SysMain (Superfetch)...' -ForegroundColor Cyan
$mediaType = 'Unknown'
try { $mediaType = (Get-PhysicalDisk | Select-Object -First 1).MediaType } catch {}
if ($mediaType -eq 'SSD') {
    $s = Get-Service -Name 'SysMain' -ErrorAction SilentlyContinue
    if ($s -and $s.StartType -ne 'Disabled') {
        $startMode = (Get-CimInstance Win32_Service -Filter "Name='SysMain'").StartMode
        $manifest.Add(('SVC|SysMain|' + $startMode))
        Set-Service -Name 'SysMain' -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host '  SSD detected -> SysMain disabled (frees RAM and disk chatter)' -ForegroundColor Green
    } else {
        Write-Host '  SysMain already disabled' -ForegroundColor DarkGray
    }
} else {
    Write-Host ('  disk media type: ' + $mediaType + ' -> SysMain left untouched (safer for HDD)') -ForegroundColor DarkGray
}

# ---------- [5/6] Temp cleanup ----------
Write-Host ''
Write-Host '[5/6] Cleaning temp files...' -ForegroundColor Cyan
$freed = 0
foreach ($t in @($env:TEMP, 'C:\Windows\Temp')) {
    if (-not (Test-Path $t)) { continue }
    $files = Get-ChildItem -Path $t -Recurse -Force -ErrorAction SilentlyContinue
    $size = ($files | Measure-Object Length -Sum -ErrorAction SilentlyContinue).Sum
    Remove-Item -Path (Join-Path $t '*') -Recurse -Force -ErrorAction SilentlyContinue
    if ($size) { $freed += $size }
}
Write-Host ('  freed ' + [math]::Round($freed / 1MB, 1) + ' MB of temp files') -ForegroundColor Green

# ---------- [6/6] Gaming memory tweaks ----------
Write-Host ''
Write-Host '[6/6] Applying memory / responsiveness tweaks...' -ForegroundColor Cyan
$mm = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
Backup-RegValue $mm 'ClearPageFileAtShutdown'
Set-ItemProperty -LiteralPath $mm -Name 'ClearPageFileAtShutdown' -Value 0 -Type DWord -ErrorAction SilentlyContinue
$sp = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
Backup-RegValue $sp 'SystemResponsiveness'
Backup-RegValue $sp 'NetworkThrottlingIndex'
Set-ItemProperty -LiteralPath $sp -Name 'SystemResponsiveness' -Value 10 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -LiteralPath $sp -Name 'NetworkThrottlingIndex' -Value 0xFFFFFFFF -Type DWord -ErrorAction SilentlyContinue
$gts = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
Backup-RegValue $gts 'GPU Priority'
Backup-RegValue $gts 'Priority'
Set-ItemProperty -LiteralPath $gts -Name 'GPU Priority' -Value 8 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -LiteralPath $gts -Name 'Priority' -Value 6 -Type DWord -ErrorAction SilentlyContinue
Write-Host '  CPU/network priority shifted toward games' -ForegroundColor Green

# ---------- save manifest ----------
$manifest | Set-Content -LiteralPath $manifestPath -Encoding ASCII

# ---------- restart explorer ----------
Write-Host ''
Write-Host 'Refreshing desktop shell...' -ForegroundColor DarkGray
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

# ---------- summary ----------
Write-Host ''
Write-Host '[DONE] BOSCOV Boost applied!' -ForegroundColor Cyan
Write-Host ''
Write-Host '  > Restart your PC once so all changes take full effect.' -ForegroundColor Yellow
Write-Host '  > You should notice: faster boot, more free RAM, less background lag.' -ForegroundColor Gray
Write-Host ('  > Backup saved to: ' + $backupDir) -ForegroundColor Gray
Write-Host '  > To undo everything, run this file again with the -Revert flag:' -ForegroundColor Gray
Write-Host '    powershell -ExecutionPolicy Bypass -File "BOSCOV Boost.ps1" -Revert' -ForegroundColor Gray
Write-Host ''
Write-Host '  BOSCOV Boost v1.0 - free to share with friends.' -ForegroundColor Cyan

Pause-Exit
