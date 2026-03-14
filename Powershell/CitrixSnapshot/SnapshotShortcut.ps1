# Variables
$batchFilePath = "C:\Windows\AVC\Scripts\USER\SelfSnapshotProvisioning\SnapshotShortcut.bat" # Full path to the batch file
$desktopPath = [Environment]::GetFolderPath("Desktop") # Path to the user's desktop
$shortcutPath = Join-Path $desktopPath "TriggerSnapshotCreation.lnk" # Name of the shortcut
$iconPath = "C:\Windows\AVC\Scripts\USER\SelfSnapshotProvisioning\SP.ico" # Full path to your icon file

# Create Shortcut
Write-Host "Creating shortcut on the Desktop..."
$wshShell = New-Object -ComObject WScript.Shell
$shortcut = $wshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $batchFilePath
$shortcut.WorkingDirectory = (Split-Path $batchFilePath)
$shortcut.IconLocation = $iconPath
$shortcut.Save()
Write-Host "Shortcut created on the Desktop with a custom icon: $shortcutPath"

# Copy shortcut to Start Menu Programs folder for all users
$startMenuPath = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs"
$startMenuShortcutPath = Join-Path $startMenuPath "TriggerSnapshotCreation.lnk"
Copy-Item -Path $shortcutPath -Destination $startMenuShortcutPath -Force
Write-Host "Shortcut copied to Start Menu Programs: $startMenuShortcutPath"