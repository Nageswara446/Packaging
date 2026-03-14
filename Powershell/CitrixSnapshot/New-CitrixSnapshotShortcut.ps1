function New-CitrixSnapshotShortcut {
    param (
        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [string]$ShortcutName = "Take VDI Snapshot"
    )

    $startMenuPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
    $shortcutPath  = Join-Path $startMenuPath "$ShortcutName.lnk"

    if (-not (Test-Path $ScriptPath)) {
        throw "Script not found: $ScriptPath"
    }

    $wshShell = New-Object -ComObject WScript.Shell
    $shortcut = $wshShell.CreateShortcut($shortcutPath)

    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments  = "-ExecutionPolicy Bypass -File `"$ScriptPath`""
    $shortcut.IconLocation = "shell32.dll,238"
    $shortcut.WindowStyle = 1
    $shortcut.Description = "Trigger Jenkins pipeline to take Azure VM snapshot"

    $shortcut.Save()
}

# ================================
# MAIN
# ================================
$scriptPath = "C:\Scripts\New-CitrixSnapshotShortcut.ps1"
New-CitrixSnapshotShortcut -ScriptPath $scriptPath
