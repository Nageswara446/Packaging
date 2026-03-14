# Delete any existing WinRM listeners
Write-Host "Deleting any existing WinRM listeners..."
winrm delete winrm/config/listener?Address=*+Transport=HTTP 2>$Null
winrm delete winrm/config/listener?Address=*+Transport=HTTPS 2>$Null

# Create a new WinRM listener and configure WinRM settings
Write-Host "Create a new WinRM listener and configure"
winrm create winrm/config/listener?Address=*+Transport=HTTP
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="0"}'
winrm set winrm/config '@{MaxTimeoutms="7200000"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service '@{MaxConcurrentOperationsPerUser="12000"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/client/auth '@{Basic="true"}'

Write-Host "Configure UAC to allow privilege elevation in remote shells"
$Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$Setting = 'LocalAccountTokenFilterPolicy'
Set-ItemProperty -Path $Key -Name $Setting -Value 1 -Force

Write-Host "turn off PowerShell execution policy restrictions"
Set-ExecutionPolicy -ExecutionPolicy Unrestricted

# Configure TrustedHosts for WinRM
Write-Host "Configuring TrustedHosts for WinRM..."
Set-Item WsMan:\localhost\Client\TrustedHosts -Value "*" -Force

# Add firewall rules to allow WinRM traffic
Write-Host "Adding firewall rules to allow WinRM traffic..."
New-NetFirewallRule -DisplayName "Allow WinRM HTTP" -Name "Allow_WinRM_HTTP" -Protocol TCP -LocalPort 5985 -Action Allow -Direction Inbound

# Configure and restart the WinRM Service; Enable the required firewall exception
Write-Host "Configuring and restarting the WinRM Service, and enabling the required firewall exception..."
Stop-Service -Name WinRM -Force
Set-Service -Name WinRM -StartupType Automatic
netsh advfirewall firewall set rule name="Windows Remote Management (HTTP-In)" new action=allow localip=any remoteip=any
Start-Service -Name WinRM

