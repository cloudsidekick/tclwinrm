#### Tclwinrm sample script
###
###  This script connects to a Windows Server host with WinRM
###  enabled and performs a series of read-only (for demo purposes)
###  commands.
###
###  Results from the WinRM service are returned in xml format,
###  however Tclwinrm takes care of extracting the data
###  and returning it back to the caller.
###
###  Reference:
###  http://msdn.microsoft.com/en-us/library/windows/desktop/aa384426(v=vs.85).aspx
###
###  Change the following lines to use your ip address / FQDN, port if not default
###  WinRM enabled user and password

lappend auto_path ../

package require tclwinrm
package require base64

set address 10.12.13.14
set port 5985
set user administrator
set pass adminpass


tclwinrm::configure http $address $port $user $pass

set script {$strComputer = $Host
	$RAM = WmiObject Win32_ComputerSystem
	$MB = 1048576
	"Installed Memory: " + [int]($RAM.TotalPhysicalMemory /$MB) + " MB"
}
set command "powershell -encodedcommand [::base64::encode -wrapchar "" [encoding convertto unicode $script]]"
set result [tclwinrm::rshell $command 120 0]
puts \n$result

set command {dir c:\ }
set result [tclwinrm::rshell $command 120 0]
puts $result

### Credit to Brandon Lawson for the following PowerShell script
### www.adminnation.com/blog/2011/07/07/let-powershell-do-an-inventory-of-your-server/

set script {$server = "localhost"
	function Get-ComputerInfo {

		$result = "" | Select-Object 'Server Name', 'Asset Tag', 'Operating System', \
		'Service Pack', Manufacturer, Model, Memory, 'xCPU', CPU, 'System Drive Total', \
		'System Free Space', 'Data Drive Total', 'Data Free Space', 'IP Address', \
		'Page File Location','Page File Size', 'Last Bootup Time', 'Up Time'
		$cs = gwmi Win32_ComputerSystem -computerName $server
		$os = gwmi Win32_OperatingSystem -computerName $server
		$cp = @(gwmi Win32_Processor -computerName $server) ##force array
		$SystemDrive = gwmi Win32_logicaldisk | Where {$_.DeviceID -eq "C:"}
		$DataDrive = gwmi Win32_logicaldisk | Where {$_.DeviceID -eq "D:"}
		$bio = gwmi Win32_bios -computerName $server
		$pf = gwmi Win32_PageFileUsage -computerName $server
		$IP = @(gwmi Win32_NetworkAdapterConfiguration -ComputerName $server | 
			Where-Object { $_.IPAddress } | Select-Object -expand IPAddress)[0]

		$hds = [math]::Round($SystemDrive.size/1GB)
		$hdfs = [math]::Round($SystemDrive.FreeSpace/1GB) ##Hard drive free space calculation
		$dds = [math]::Round($DataDrive.size/1GB)
		$ddfs = [math]::Round($DataDrive.FreeSpace/1GB) ##Hard drive free space calculation
		$mem = [math]::Round($cs.totalphysicalmemory/1GB,2)
		$lastbootuptime = $os.ConvertToDateTime($os.LastBootUpTime)
		$starttime = $OS.converttodatetime($OS.LastBootUpTime)
		$uptime = New-TimeSpan (get-date $Starttime)
		$result.'Server Name' = $cs.name
		$result.'Asset Tag' = $bio.SerialNumber
		$result.Manufacturer = $cs.manufacturer
		$result.Model = $cs.model
		$result.Memory = [string]$mem + " GB"
		$result.'Operating System' = $os.Caption
		$result.'Service Pack' = $os.CSDVersion
		$result.'xCPU' = $cp.count
		$result.CPU = $cp[0].name
		$result.'System Drive Total' = [string]$hds + " GB"
		$result.'System Free Space' = [string]$hdfs + " GB"
		$result.'Data Drive Total' = [string]$dds + " GB"
		$result.'Data Free Space' = [string]$ddfs + " GB"
		$result.'IP Address' = $IP
		$result.'Page File Location' = $pf.Name
		$result.'Page File Size' = [string]$pf.AllocatedBaseSize + " MB"
		$result.'Last Bootup Time' =$lastbootuptime
		$result.'Up Time' = [string]$uptime.days + " Days " + $uptime.hours + "h " \
			+ $uptime.minutes + "m " + $uptime.seconds + "s"
		$result

	}
	Get-ComputerInfo
}


set command "powershell -encodedcommand [::base64::encode -wrapchar "" [encoding convertto unicode $script]]"
set result [tclwinrm::rshell $command 120 0]
puts $result


