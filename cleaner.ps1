param(
    [ValidateSet('Clean', 'Enable', 'Disable')]
    [string]$Action = 'Clean'
)

$TaskName = 'WindowsSystemDeepCleaner'
$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LogPath {
    $besideScript = Join-Path $PSScriptRoot 'cleaner.log'
    try {
        $stream = [System.IO.File]::Open($besideScript, 'OpenOrCreate', 'Write', 'Read')
        $stream.Dispose()
        return $besideScript
    } catch {
        $directory = Join-Path $env:ProgramData 'WindowsSystemDeepCleaner'
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        return (Join-Path $directory 'cleaner.log')
    }
}

function Write-Log {
    param([string]$Message)
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
}

function Test-ContainsScript {
    param([string]$FullName)
    $candidate = [System.IO.Path]::GetFullPath($FullName).TrimEnd('\')
    $root = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
    if ($candidate.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    return $root.StartsWith($candidate + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Remove-OneItem {
    param(
        [string]$FullName,
        [hashtable]$Result
    )

    $item = Get-Item -LiteralPath $FullName -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        try {
            $item.Delete()
            $Result.Removed++
        } catch {
            $Result.Failed.Add($FullName)
            Write-Log ("FAILED  " + $FullName + "  " + $_.Exception.Message)
        }
        return
    }

    try {
        Remove-Item -LiteralPath $FullName -Recurse -Force -ErrorAction Stop
        $Result.Removed++
        return
    } catch {
        & attrib.exe -R -S -H $FullName /S /D 2>$null | Out-Null
        & attrib.exe -R -S -H $FullName 2>$null | Out-Null
    }

    try {
        Remove-Item -LiteralPath $FullName -Recurse -Force -ErrorAction Stop
        $Result.Removed++
    } catch {
        $Result.Failed.Add($FullName)
        Write-Log ("FAILED  " + $FullName + "  " + $_.Exception.Message)
    }
}

function Clear-FolderContents {
    param(
        [string]$Folder,
        [hashtable]$Result
    )

    if (-not (Test-Path -LiteralPath $Folder)) {
        Write-Log "SKIP    $Folder"
        return
    }

    Write-Log "CLEAR   $Folder"
    Get-ChildItem -LiteralPath $Folder -Force | ForEach-Object {
        if (Test-ContainsScript $_.FullName) {
            if ($_.PSIsContainer) {
                $scriptRoot = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
                $child = [System.IO.Path]::GetFullPath($_.FullName).TrimEnd('\')
                if (-not $child.Equals($scriptRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                    Clear-FolderContents -Folder $_.FullName -Result $Result
                }
            }
            return
        }
        Remove-OneItem -FullName $_.FullName -Result $Result
    }
}

function Clear-RecycleBins {
    param([hashtable]$Result)

    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Log ("RECYCLE current user: " + $_.Exception.Message)
    }

    $drives = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3'
    foreach ($drive in $drives) {
        $binRoot = Join-Path ($drive.DeviceID + '\') '$Recycle.Bin'
        if (-not (Test-Path -LiteralPath $binRoot)) {
            continue
        }

        Write-Log "CLEAR   $binRoot"
        Get-ChildItem -LiteralPath $binRoot -Force -ErrorAction SilentlyContinue | ForEach-Object {
            Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne 'desktop.ini' } |
                ForEach-Object {
                    Remove-OneItem -FullName $_.FullName -Result $Result
                }
        }
    }
}

function Invoke-Clean {
    $script:LogPath = Get-LogPath
    $result = @{
        Removed = 0
        Failed  = New-Object System.Collections.Generic.List[string]
    }

    Write-Log 'START   clean Downloads, Documents, and Recycle Bin'
    $profiles = @(Get-CimInstance Win32_UserProfile | Where-Object {
            -not $_.Special -and $_.LocalPath -like 'C:\Users\*' -and (Test-Path -LiteralPath $_.LocalPath)
        })

    if ($profiles.Count -eq 0) {
        Write-Log 'WARN    no user profiles found under C:\Users'
    }

    foreach ($profile in $profiles) {
        Clear-FolderContents -Folder (Join-Path $profile.LocalPath 'Downloads') -Result $result
        Clear-FolderContents -Folder (Join-Path $profile.LocalPath 'Documents') -Result $result
    }

    Clear-RecycleBins -Result $result
    Write-Log ("DONE    removed=$($result.Removed) failed=$($result.Failed.Count)")
}

function Enable-CleanerTask {
    if (-not (Test-IsAdmin)) {
        throw 'Please run enable-startup.bat as Administrator.'
    }

    $scriptPath = $PSCommandPath
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "cleaner.ps1 was not found at $scriptPath"
    }

    $argument = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $argument
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Clears Downloads, Documents, and Recycle Bin at startup.' -Force | Out-Null
    Enable-ScheduledTask -TaskName $TaskName | Out-Null

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        throw 'Task Scheduler did not keep the auto-cleaner task.'
    }
    if ($task.State -eq 'Disabled') {
        throw 'The auto-cleaner task was registered but is still disabled.'
    }

    $registeredArgument = [string]$task.Actions[0].Arguments
    if ($registeredArgument.IndexOf($scriptPath, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw 'The scheduled task does not point at this cleaner.ps1.'
    }

    $account = [string]$task.Principal.UserId
    if ($account -ne 'SYSTEM' -and $account -ne 'S-1-5-18' -and $account -notlike '*\SYSTEM') {
        throw "The scheduled task is not running as SYSTEM (account: $account)."
    }

    $logPath = Get-LogPath
    Write-Host ''
    Write-Host '========================================================'
    Write-Host '[SUCCESS] Auto-cleaner task successfully enabled.'
    Write-Host "Task:   $TaskName"
    Write-Host 'Run:    at every startup, as SYSTEM'
    Write-Host "Script: $scriptPath"
    Write-Host "Log:    $logPath"
    Write-Host '========================================================'
}

function Disable-CleanerTask {
    if (-not (Test-IsAdmin)) {
        throw 'Please run disable-startup.bat as Administrator.'
    }

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    $stillThere = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($stillThere) {
        throw 'Task Scheduler still has the auto-cleaner task.'
    }

    Write-Host ''
    Write-Host '========================================================'
    if ($task) {
        Write-Host '[SUCCESS] Auto-cleaner task successfully disabled.'
    } else {
        Write-Host '[SUCCESS] Auto-cleaner task is already disabled.'
    }
    Write-Host "Task: $TaskName"
    Write-Host '========================================================'
}

try {
    switch ($Action) {
        'Enable' { Enable-CleanerTask }
        'Disable' { Disable-CleanerTask }
        default { Invoke-Clean }
    }
} catch {
    if ($script:LogPath) {
        Write-Log ("ERROR   " + $_.Exception.Message)
    }
    Write-Host ''
    Write-Host '[ERROR]' $_.Exception.Message
    exit 1
}

exit 0
