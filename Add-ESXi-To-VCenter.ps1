<# 
    Add multiple ESXi to vCenter
	Created by Hakan Akkurt
    Jan 2018
    version 1.0
#>

# Parameters
$VIServer = "dt-odc3-vcsa01.onat.local"
$VIUsername = "administrator@vsphere.local"
$VIPassword = "VMware1!"
$verboseLogFile = "ScriptLogs.log"
$ESXiListFile="C:\Scripts\vSphere\ESXi-List.csv"
$DatacenterName ="DC-ODC3"
$ClusterName ="CL-ODC3-COMP01"
$ESXiPassword = "VMware1!" 


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

if(!(Test-Path $ESXiListFile)) {
		Write-Host -ForegroundColor Red "`nUnable to find $ESXiListFile ...`nexiting"
		exit
	}

$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue

		$Cluster = Get-Cluster -Name $ClusterName -Location $Datacenter
						
		$csv=Import-Csv $ESXiListFile
			   
			foreach($cell in $csv){
				$ESXiName= $cell.ESXiName
				My-Logger "Adding ESXi host $ESXiName to Cluster ..."
				Add-VMHost -Server $viConnection -Location $Cluster -User "root" -Password $ESXiPassword -Name $ESXiName -Force | Out-File -Append -LiteralPath $verboseLogFile
				
			}
	
Disconnect-VIServer -Server $VIServer -confirm:$false | out-null

