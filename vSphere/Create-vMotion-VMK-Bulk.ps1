<# 
    Create vMotion VMKernel by using vMotion TCP/IP Stack
	Created by Hakan Akkurt
    Feb 2018
    version 1.0
#>

# Parameters
$VIServer = "vcenter.poc.local"
$VIUsername = "administrator@vsphere.local"
$VIPassword = "VMware1!"
$verboseLogFile = "ScriptLogs.log"

$ManagementVMK = "vmk0"
$vMotionIPSegment="192.168.2."
$vDSName = "vDS"
$vMotionPGName ="vMotion"

Find-Module VMware.PowerCLI | Install-Module -Scope CurrentUser -Confirm:$False

Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -confirm:$false | out-null
Set-PowerCLIConfiguration -invalidcertificateaction Ignore -confirm:$false | out-null
Set-PowerCLIConfiguration -Scope Session -WebOperationTimeoutSeconds 3600 -confirm:$false | out-null

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
							
							$VMHostName = $VMHost.name		
							
							# Get Management VMK IP
							
							$ManagementVMKIP=Get-VMHost $VMHostName | Sort Name | Get-View | Select @{N="IP Address";E={($_.Config.Network.Vnic | ? {$_.Device -eq "$ManagementVMK"}).Spec.Ip.IpAddress}}
							$IP=$ManagementVMKIP.'IP Address'						
							$str = $IP.split(".")
							$LastOctet =$str[3]
							$vMotionVMKIP=$vMotionIPSegment+$LastOctet
							
							# Create vMotion VMK
							$portgoup = Get-VDPortgroup -Name $vMotionPGName
				 			$nic = New-Object VMware.Vim.HostVirtualNicSpec
							$distributedVirtualPort = New-Object VMware.Vim.DistributedVirtualSwitchPortConnection
							$nic.distributedVirtualPort = $distributedVirtualPort
							$nic.distributedVirtualPort.portgroupKey = $portgoup.key
							$nic.distributedVirtualPort.switchUuid = $portgoup.VDSwitch.key
							$nic.netStackInstanceKey = 'vmotion'
							$ip = New-Object VMware.Vim.HostIpConfig
							$ip.ipAddress = $vMotionVMKIP
							$ip.subnetMask = '255.255.255.0'
							$ip.dhcp = $false
							$ip.ipV6Config = New-Object VMware.Vim.HostIpConfigIpV6AddressConfiguration
							$ip.ipV6Config.dhcpV6Enabled = $false
							$ip.ipV6Config.autoConfigurationEnabled = $false
							$ip.IpV6Config = $ipV6Config
							$nic.Ip = $ip			 

							$networkSystem = $VMHost.ExtensionData.configManager.NetworkSystem
							$_this = Get-view -Id ($networkSystem.Type + "-" + $networkSystem.Value)
							$_this.AddVirtualNic('', $nic) | out-null
							
							My-Logger "Setting vMotion VMKernel for $VMHostName with $vMotionVMKIP IP"
						
						}
						My-Logger "Operation completed"
				}
		}
		
Disconnect-VIServer -Server $VIServer -confirm:$false | out-null