# SRM Disaster Avoidance Script

set-powercliconfiguration -invalidcertificateaction "ignore" -confirm:$false |out-null

$VIServer = "dt-odc3-vcsa01.onat.local"
$PSCServer = "dt-odc3-psc01.onat.local"
$VIUsername = "administrator@vsphere.local"
$VIPassword = "VMware1!"

# NSX Parameters
$NSXHostname = "dt-odc4-nsx01.onat.local"
$NSXUIPassword = "VMware1!"
$PLR1Name = "ESG3"
$PLR2Name = "ESG4"
$UDLRName = "UDLR2"

$NSXHostname2 = "dt-odc3-nsx01.onat.local"
$NSXUIPassword2 = "VMware1!"
$PLR1Name2 = "ESG1"
$PLR2Name2 = "ESG2"
$UDLRName2 = "UDLR1"

$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue

$srmConnection=Connect-SRMServer

	try {
	 
		if(!(Connect-NSXServer -Server $NSXHostname2 -Username admin -Password $NSXUIPassword2 -DisableVIAutoConnect -WarningAction SilentlyContinue)) {
				Write-Host -ForegroundColor Red "Unable to connect to NSX Manager, please check the deployment"
				exit
			} 
		else {
				Write-Host "Successfully logged into NSX Manager $NSXHostname2..."
			}
		
		}
		
	catch {
        Throw  "Error while connecting NSX Manager"
    }  
	
	$interfaces = Get-NsxLogicalRouter -Name $UDLRName2  | Get-NsxLogicalRouterInterface
	
	
	foreach($interface in $interfaces)
	{
		if($interface.type -eq "uplink")
		{
			$UDLRulinkip=$interface.addressGroups.addressGroup.primaryAddress 
		}
	}
	
Disconnect-NsxServer
	 
	try {
	 
		if(!(Connect-NSXServer -Server $NSXHostname -Username admin -Password $NSXUIPassword -DisableVIAutoConnect -WarningAction SilentlyContinue)) {
				Write-Host -ForegroundColor Red "Unable to connect to NSX Manager, please check the deployment"
				exit
			} 
		else {
				Write-Host "Successfully logged into NSX Manager $NSXHostname..."
			}
		
		}
		
	catch {
        Throw  "Error while connecting NSX Manager"
    }  
	
	
	$srmpgs = $srmApi.Protection.ListProtectionGroups()

	for ($i=0; $i -lt $srmpgs.Count; $i++)
	{
	
	$pgname = $srmapi.protection.listprotectiongroups()[$i].GetInfo().Name
	$pgname
	

		$vms = $srmpgs[$i].ListProtectedVMs()
		for ($a=0; $a -lt $vms.Count; $a++)
		{
			$vm = get-vm -ID $vms[$a].VM.MoRef
			$pgvms = $vm.Name
			$IPAddress = $vm.Guest.IPAddress[0]
			$Edge1 = Get-NsxEdge $PLR1Name
			$Edge2 = Get-NsxEdge $PLR2Name
			$Edge1 | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network "$IPAddress/32" -NextHop $UDLRulinkip -confirm:$false
			$Edge2 | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network "$IPAddress/32" -NextHop $UDLRulinkip -confirm:$false
			Write-Host "$pgvms : $IPAddress"
		}
	}	
		
Disconnect-VIServer -Server $viConnection -confirm:$false
Disconnect-NsxServer