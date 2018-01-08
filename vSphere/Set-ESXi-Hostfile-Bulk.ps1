<# 
    Add etc/hosts file records to multiple ESXi Hosts
	Created by Hakan Akkurt
    Jan 2018
    version 1.0
#>

# Parameters
$VIServer = "dt-odc3-vcsa01.onat.local"
$VIUsername = "administrator@vsphere.local"
$VIPassword = "VMware1!"
$verboseLogFile = "ScriptLogs.log"
$ESXiUsername = "root" 
$ESXiPassword = "VMware1!" 


#New Host Entry
$addIP = "192.168.1.151"
$addHostname = "newhostsname"


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
					
							### Create authorization string and store in $head
							$auth = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($ESXiUsername + ":" + $ESXiPassword))
							$head = @{"Authorization"="Basic $auth"}

							# Request current hosts file
							Write-Host "Retrieving current /etc/hosts file from $VMHostName" -ForeGroundColor Green
							$requesthostsfile = Invoke-WebRequest -Uri https://$VMHostName/host/hosts -Method GET -ContentType "text/plain" -Headers $head

							if ( $requesthostsfile.StatusCode -ne "200" ) {
							   Write-Host "Unable to retrieve current /etc/hosts file from $VMHostName" -ForeGroundColor Red
							   Exit
							}

							# Add new line to hosts file with $addIP and $addHostname
							$newhostsfile = $requesthostsfile.Content
							$newhostsfile += "`n$addIP`t$addHostname`n"

							Write-Host "Contents of new /etc/hosts" -ForeGroundColor Green
							Write-Host "-------------------------------------------------------"
							Write-Host $newhostsfile
							Write-Host "-------------------------------------------------------"

							# Put the new hosts file on the host
							Write-Host "Putting new /etc/hosts file on $VMHostName"
							$puthostsfile = Invoke-WebRequest -Uri https://$VMHostName/host/hosts -Method PUT -ContentType "text/plain" -Headers $head -Body $newhostsfile

							if ( $puthostsfile.StatusCode -ne "200" ) {
							   Write-Host "Unable to put new /etc/hosts file on $VMHostName" -ForeGroundColor Red
							   Exit
							}
							Write-Host "Done!" -ForeGroundColor Green
						
						
						
						}
				}
		}
		
		
		
Disconnect-VIServer -Server $VIServer -confirm:$false | out-null
