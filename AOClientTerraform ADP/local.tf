locals {
#  virtual_machine_fqdn = join(".", [var.vm_name, var.ad_domain_name])
  auto_logon_data      = "<AutoLogon><Password><Value>${var.admin_password}</Value></Password><Enabled>true</Enabled><LogonCount>1</LogonCount><Username>${var.admin_username}</Username></AutoLogon>"
  first_logon_data     = file("${path.module}/files/FirstLogonCommands.xml")
  adduser_command      = "Add-LocalGroupMember -Group Administrators -Member ${var.admin_username}"
  enable_command       = "enable-wsmanCredSSP -role Server -Force"
  configure_command    = "Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -Confirm:$False"
  cleanup_command      = "Remove-Item C:/Terraform/ -Recurse"
  move_cdrom           = "Get-WmiObject -Class Win32_volume -Filter 'DriveType=5' | Select-Object -First 1 | Set-WmiInstance -Arguments @{DriveLetter='A:'}"
  format_diskd         = "Get-Disk|Where-object partitionstyle -eq 'raw'|Initialize-Disk -PartitionStyle GPT -PassThru|New-Partition -AssignDriveLetter -UseMaximumSize|Format-Volume -FileSystem NTFS -NewFileSystemLabel 'New Volume' -Confirm:$false"
  extend_c             = "$size = (Get-PartitionSupportedSize -DriveLetter C);Resize-Partition -DriveLetter C -Size $size.SizeMax;"
  reboot_command       = "shutdown -r -t 30"
  exit_code            = "exit 0"
  powershell_command   = "${local.adduser_command}; ${local.enable_command}; ${local.configure_command}; ${local.cleanup_command}; ${local.move_cdrom}; ${local.format_diskd}; ${local.extend_c}; ${local.reboot_command}; ${local.exit_code}"
}