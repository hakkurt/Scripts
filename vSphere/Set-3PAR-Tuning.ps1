<# 
    Set ESXi Parameters based on 3PAR Recommendations
    Created by Hakan Akkurt
    May 2018
    version 1.0
#>

# Parameters
$VIServer = "vcsa-01a.corp.local"
$VIUsername = "administrator@vsphere.local"
$VIPassword = "VMware1!"
$verboseLogFile = "ScriptLogs.log"


Find-Module VMware.PowerCLI | Install-Module -Scope CurrentUser -Confirm:$False

Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -confirm:$false | out-null
Set-PowerCLIConfiguration -invalidcertificateaction Ignore -confirm:$false | out-null

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
			
	$VMHosts=Get-VMHost 
	
		foreach ($VMHost in $VMHosts) {
			
			$VMHostName = $VMHost.name	

			My-Logger "Setting PSP as Round Robin for $VMHostName ...."
			Get-VMhost $VMHost | Get-ScsiLun -LunType disk -CanonicalName "naa.6000*" | Set-ScsiLun -MultipathPolicy "RoundRobin" | out-null
			
			My-Logger "Changing IOPS = 1 $VMHostName ...."
			Get-VMHost $VMHost.name  | Get-ScsiLun -LunType disk | Where-Object {$_.Multipathpolicy -like "RoundRobin"} | Set-ScsiLun -CommandsToSwitchPath 1 | out-null

			My-Logger "Set QFullSampleSize = 32 for $VMHostName ...."
 
			$VMHost | Get-AdvancedSetting -Name "Disk.QFullSampleSize" |  Set-AdvancedSetting -Value 32 -Confirm:$false | out-null

			My-Logger "Set QFullThreshold = 4 for $VMHostName ...."
			$VMHost | Get-AdvancedSetting -Name "Disk.QFullThreshold" |  Set-AdvancedSetting -Value 4 -Confirm:$false | out-null
					
 			My-Logger "--------------------------------------"
			
		}
		
		
Disconnect-VIServer -Server $VIServer -confirm:$false | out-null
