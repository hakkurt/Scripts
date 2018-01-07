<# 
    Set NTP server for all ESXi Hosts
	Created by Hakan Akkurt
    Jan 2018
    version 1.0
#>

# Deployment Parameters
$VIServer = "dt-odc3-vcsa01.onat.local"
$VIUsername = "administrator@vsphere.local"
$VIPassword = "VMware1!"
$verboseLogFile = "ScriptLogs.log"
$NTPServer = "10.97.2.10"


Find-Module VMware.PowerCLI | Install-Module –Scope CurrentUser -Confirm:$False

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

My-Logger "NTP Server will be set to : $NTPServer..." 

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
								
							$ntp = Get-VMHostNtpServer -VMHost $VMHost
							
							My-Logger "Clearing current NTP Server for $VMHostName..."
							Remove-VMHostNtpServer -VMHost $VMHost -NtpServer $ntp -Confirm:$false | out-null
							
							My-Logger "Setting NTP Server for $VMHostName..."
							Get-VMHost $VMHost | Add-VMHostNtpServer -NtpServer $NtpServer | out-null
							
							#Checking NTP Service on the ESXi host
							$ntp = Get-VMHostService -vmhost $VMHost| ? {$_.Key -eq 'ntpd'}
							Set-VMHostService $ntp -Policy on | out-null

							if ($ntp.Running ){
							Restart-VMHostService $ntp -confirm:$false | out-null
							My-Logger "$ntp Service on $VMHost was On and was restarted"
							}
							Else{
							Start-VMHostService $ntp -confirm:$false | out-null
							My-Logger "$ntp Service on $VMHost was Off and has been started"
							}
							
						
						}
				}
		}
		
Disconnect-VIServer -Server $VIServer -confirm:$false | out-null