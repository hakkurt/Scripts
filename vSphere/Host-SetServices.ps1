<# 
    Set ESXi Advanced Settings
	Created by Hakan Akkurt
    Feb 2018
    version 1.1
#>

# Parameters
$VIServer = "vcenter.poc.local"
$VIUsername = "administrator@vsphere.local"
$VIPassword = "VMware1!"
$DCUIAccess = "root"
$HostUserName = "root"
$HostUserPassword = "vmware1!"
$verboseLogFile = "ScriptLogs.log"

Clear

Function My-Logger {
    param(
    [Parameter(Mandatory=$true)]
    [String]$message
    )

    $timeStamp = Get-Date -Format "dd-MM-yyyy_hh:mm:ss"

    Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
    Write-Host -ForegroundColor Green " $message"
    $logMessage = "[$timeStamp] $message"
    $logMessage | Out-File -Append -LiteralPath $verboseLogFile
}

$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue

$Datacenters=Get-Datacenter
		
		foreach ($Datacenter in $Datacenters) {
				
			$DatacenterName = $Datacenter.name
			Write-Host -ForegroundColor Yellow "Datacenter Name : "$DatacenterName
			$Clusters = Get-Cluster -Location $Datacenter
				
				foreach ($Cluster in $Clusters) {
					
					$ClusterName = $Cluster.name										
					
					$VMHosts=Get-VMHost -Location $ClusterName
					
						foreach ($VMHost in $VMHosts) {
							
							$HostIP = $VMHost.name
							
							Write-Host "Name is $HostIP"
							$results = Connect-VIServer -Server $HostIP -user $HostUserName -Password $HostUserPassword -WarningAction silentlycontinue
							If ($results -ne $null){
							Write-Output "*****************************[$HostIP]**********************************"
							Write-Output "[HOST-$HostIP] Connected"
			
			#Disable MOB
			$MOB=Get-VmHostAdvancedConfiguration -Name Config.HostAgent.plugins.solo.enableMob -WarningAction silentlycontinue | out-null
			if($MOB.Values -ne $false){
				Set-VMHostAdvancedConfiguration -Name Config.HostAgent.plugins.solo.enableMob  -Value false -WarningAction silentlycontinue | out-null
				Write-Output "[HOST-$HostIP] MOB Disabled"
			}
			else{
				Write-Output "[HOST-$HostIP] MOB already Disabled"
			}
			
			#Set ESXiShellInteractiveTimeOut
			Set-VMHostAdvancedConfiguration -Name "UserVars.ESXiShellInteractiveTimeOut" -Value 900 -WarningAction silentlycontinue | out-null
			Write-Output "[HOST-$HostIP] set ESXiShellInteractiveTimeOut 15 mins "
			
			# Set Remove UserVars.ESXiShellTimeOut to 900 on all hosts
			Set-VMHostAdvancedConfiguration -Name "UserVars.ESXiShellTimeOut" -Value 900 -WarningAction silentlycontinue | out-null
			
			
			#DCUI.Access
			Get-AdvancedSetting -Entity $HostIP | Where-Object -FilterScript { $_.Name -eq 'DCUI.Access'  } | Set-AdvancedSetting -Value $DCUIAccess -Confirm:$false -ErrorAction Stop
		
			#set Net.BlockGuestBPDU 
			Set-VMHostAdvancedConfiguration -Name "Net.BlockGuestBPDU" -Value 1 -WarningAction silentlycontinue | out-null
			Write-Output "[HOST-$HostIP] set BlockGuestBPDU value 1"
			
			Disconnect-VIServer -Server $HostIP -confirm:$false
			Write-Output "[HOST-$HostIP] Disconnected"
			Write-Host
		}
		else{
			Write-Error "[Host-$HostIP] ERROR: Unable to connect"
		}			
							My-Logger "Setting Services for $VMHostName"
						
						}
						My-Logger "Operation completed"
				}
		}
		
Disconnect-VIServer -Server $VIServer -confirm:$false | out-null