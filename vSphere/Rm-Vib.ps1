<# 
    Remove VIB
    Created by Hakan Akkurt
    May 2018
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
			
			My-Logger "Stopping sfcbd-watchdog service for $VMHostName ...."
			Get-VMHost -Name $VMHostName | Get-VMHostService | ?{"sfcbd-watchdog" -contains $_.Key} | Stop-VMHostService -confirm:$false  | out-null
			
			My-Logger "Removing intelcim-provider for $VMHostName ...."
			$esxcli = get-esxcli -V2 -vmhost  $VMHost
			$esxcli.software.vib.remove.Invoke(@{"vibname" = "intelcim-provider"})
			
			My-Logger "Starting sfcbd-watchdog service for $VMHostName ...."
			Get-VMHost -Name $VMHostName | Get-VMHostService | ?{"sfcbd-watchdog" -contains $_.Key} | Start-VMHostService | out-null
			My-Logger "--------------------------------------"
			
			
		}
		
Disconnect-VIServer -Server $VIServer -confirm:$false | out-null
