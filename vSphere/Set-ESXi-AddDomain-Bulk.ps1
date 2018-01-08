<# 
    Add ESXi Hosts to AD domain, allow firewall, change advanced settings
    Created by Hakan Akkurt
    Jan 2018
    version 1.0
#>

# Parameters
$VIServer = "dt-odc3-vcsa01.onat.local"
$VIUsername = "administrator@vsphere.local"
$VIPassword = "VMware1!"
$verboseLogFile = "ScriptLogs.log"
$DomainName="onat.local"
$DomainUser="administrator"
$DomainUserPass="VMware1!"
$esxAdminsGroup="ESX Admins"


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
							
							# ESXi Firewall Configuration
							
							My-Logger "Setting ESXi Firewall for $VMHostName"
						
							$firewallpolicy = Get-VMHostFirewallDefaultPolicy -VMHost $VMHost

							Set-VMHostFirewallDefaultPolicy -Policy $firewallpolicy -AllowOutgoing $true -AllowIncoming $true | out-null
							My-Logger "... Waiting 10 sec ..."
							Sleep 10
								
							# Domain join
							
							My-Logger "Adding $VMHostName to $DomainName Domain ...."
							Get-VMHostAuthentication -VMHost $VMHost | Set-VMHostAuthentication -Domain $DomainName -User $DomainUser -Password $DomainUserPass -JoinDomain -Confirm:$false | out-null
							My-Logger "... Waiting 30 sec ..."
							Sleep 30
								
							# Change ESXi Advanced Settings
							
							My-Logger "Changing Config.HostAgent.plugins.hostsvc.esxAdminsGroup parameter for $VMHostName ...."
							Get-AdvancedSetting -Entity (Get-VMHost $VMHost) -Name Config.HostAgent.plugins.hostsvc.esxAdminsGroup | Set-AdvancedSetting -Value $esxAdminsGroup  -confirm:$false | out-null
							
						}
				}
		}
		
Disconnect-VIServer -Server $VIServer -confirm:$false | out-null
