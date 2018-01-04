<# 
    Cross-VC NSX Recovery script
	Created by Hakan Akkurt
    Jan 2018
    version 1.2
#>

# Check PowerCli and PowerNSX modules

Install-Module -Name VMware.PowerCLI –Scope CurrentUser
Find-Module PowerNSX | Install-Module -scope CurrentUser

Set-PowerCLIConfiguration -invalidcertificateaction Ignore -confirm:$false |out-null
Set-PowerCLIConfiguration -Scope Session -WebOperationTimeoutSeconds 3600 -confirm:$false |out-null

$VIServer = "dt-odc4-vcsa01.onat.local"
$VIUsername = "administrator@vsphere.local"
$VIPassword = "VMware1!"

# NSX Parameters

$NSXHostname = "dt-odc4-nsx01.onat.local"
$NSXUIPassword = "VMware1!"
$UDLR1Name = "UDLR1"

$ControllerNetworkPortGroupName = "PG-Management"
$ControllerCluster = "CL-ODC4-COMP01"
$ControllerDatastore = "ODC4-LDS2-esxi02"
$ControllerPassword = "VMware1!VMware1!"

# Edit if you didn't configure Controller IP Pool before 
$ControllerPoolStartIp = "10.97.30.181"
$ControllerPoolEndIp = "10.97.30.183"
$ControllerNetworkSubnetMask = "255.255.255.0"
$ControllerNetworkSubnetPrefixLength ="24"
$ControllerNetworkGateway = "10.97.30.11"


$StartTime = Get-Date

$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue

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
	
	# NSX Recovery Steps
	Write-Host -foregroundcolor Yellow "NSX Component Recovery is started..."
	
	# Step 1
	Write-Host -foregroundcolor Green "Disconnect $NSXHostname from the Primary NSX Manager..."
	Set-NsxManagerRole Standalone -WarningAction Ignore
	
	Write-Host -foregroundcolor Green "Promote  $NSXHostname from Secondary to Primary..."
	Set-NsxManagerRole Primary -WarningAction Ignore
	
	# Step 2
	Write-Host -foregroundcolor Green "Deploying NSX Controllers..."
			
		 try {
		 
			$cluster = Get-Cluster -Name $ControllerCluster -errorAction Stop
			$datastore = Get-Datastore -Name $ControllerDatastore -errorAction Stop
			$PortGroup = Get-VdPortGroup $ControllerNetworkPortGroupName -errorAction Stop
			
			$ControllerPool = Get-NsxIpPool -Name "ControllerPool"
			
			if(!$ControllerPool){		 
				Write-Host "   -> Creating IP Pool for Controller addressing"
				$ControllerPool = New-NsxIpPool -Name "ControllerPool" -Gateway $ControllerNetworkGateway -SubnetPrefixLength $ControllerNetworkSubnetPrefixLength -StartAddress $ControllerPoolStartIp -EndAddress $ControllerPoolEndIp 
			}
			
				for ( $i=1; $i -le 3; $i++ ) {

					Write-Host "   -> Deploying NSX Controller $($i)"

					$Controller = New-NsxController -IpPool $ControllerPool -Cluster $cluster -datastore $datastore -PortGroup $PortGroup  -password $ControllerPassword -confirm:$false -wait
			 
					Write-Host "   -> Controller $($i) online."
				}
			}
			
			catch {

			Throw  "Failed deploying controller Cluster.  $_"
			}
		
	
	# Step 3
	Write-Host "Update Controller State.."
	$apistr="/api/2.0/vdn/controller/synchronize"
	 
	Invoke-NsxRestMethod -Method put -Uri $apistr -InformationAction:SilentlyContinue

	# Step 4
	Write-Host "Deploying UDLR CVMs.."
		
	$clusterMoRef = $cluster.Id
	$datastoreMoref = $datastore.Id
	
	$clusterMoRef=$clusterMoRef.Replace("ClusterComputeResource-","")
	$datastoreMoref=$datastoreMoref.Replace("Datastore-","")
		
	$UDLR = Get-NsxLogicalRouter -name $UDLR1Name
		
	$UDLRid = $UDLR.id
	$apistr="/api/4.0/edges/$UDLRid"
	$UDLRXML=Invoke-NsxRestMethod  -Method get -Uri $apistr  | out-null
		
	$appliances=$UDLRXML.SelectSingleNode("//appliances")
	$child = $UDLRXML.CreateElement("appliance")
	$appliances.AppendChild($child) | out-null
	
	$appliances=$UDLRXML.SelectSingleNode("//appliance")
	$child = $UDLRXML.CreateElement("datastoreId")
	$appliances.AppendChild($child) | out-null
	
	$child = $UDLRXML.CreateElement("resourcePoolId")
	$appliances.AppendChild($child) | out-null
		
	$element = $UDLRXML.SelectSingleNode("//datastoreId")
	$element.InnerText =$datastoreMoref
	
	$element = $UDLRXML.SelectSingleNode("//resourcePoolId")
	$element.InnerText =$clusterMoRef
			
	$UDLRXML.Save('C:\scripts\$UDLRid.xml')
	$body=$UDLRXML.OuterXml
	Invoke-NsxRestMethod  -Method put -Uri $apistr -body $body | out-null

	Write-Host -foregroundcolor Yellow "NSX Component Recovery is completed..."
	
	$EndTime = Get-Date
	$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)

	Write-Host "Duration: $duration minutes"

	Disconnect-VIServer -Server $VIServer 
	Disconnect-NsxServer
