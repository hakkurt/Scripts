<# 
    Start ESXi Service
	Created by Hakan Akkurt
    Jan 2018
    version 1.0
#>

# Parameters
$VIServer = "dt-odc3-vcsa01.onat.local"
$VIUsername = "administrator@vsphere.local"
$VIPassword = "VMware1!"
$verboseLogFile = "ScriptLogs.log"


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
					Write-Host -ForegroundColor Yellow "	Cluster Name : "$ClusterName					
					
					$VMHosts=Get-VMHost -Location $ClusterName
					
						foreach ($VMHost in $VMHosts) {
							
							$VMHostName = $VMHost.name		
							
							My-Logger "Starting lwsmd service for $VMHostName ...."
							Get-VMHost -Name $VMHostName | Get-VMHostService | ?{"lwsmd" -contains $_.Key} | Start-VMHostService
							
						}
				}
		}
		
Disconnect-VIServer -Server $VIServer -confirm:$false | out-null