<# 
    Cross-VC NSX Recovery script
	Created by Hakan Akkurt
    Jan 2018
    version 1.3
#>

# Check PowerCli and PowerNSX modules

Find-Module VMware.PowerCLI | Install-Module -Name VMware.PowerCLI –Scope CurrentUser -Confirm:$False
Find-Module PowerNSX | Install-Module -scope CurrentUser -Confirm:$False

Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -confirm:$false | out-null
Set-PowerCLIConfiguration -invalidcertificateaction Ignore -confirm:$false | out-null
Set-PowerCLIConfiguration -Scope Session -WebOperationTimeoutSeconds 3600 -confirm:$false | out-null

$verboseLogFile = "NSX-Recovery.log"

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

$StartTime = Get-Date

$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue

	try {
	 
		if(!(Connect-NSXServer -Server $NSXHostname -Username admin -Password $NSXUIPassword -DisableVIAutoConnect -WarningAction SilentlyContinue)) {
				My-Logger "Unable to connect to NSX Manager, please check the deployment"
				exit
			} 
		else {
				My-Logger "Successfully logged into NSX Manager $NSXHostname..."
			}
		
		}
		
	catch {
		My-Logger "Error while connecting NSX Manager"
        Throw  "Error while connecting NSX Manager"
    }  
	
	# NSX Recovery Steps
	My-Logger "NSX Component Recovery is started..."
	
	# Step 1
	My-Logger "Disconnect $NSXHostname from the Primary NSX Manager..."
	Set-NsxManagerRole Standalone -WarningAction SilentlyContinue
	
	My-Logger "Promote  $NSXHostname from Secondary to Primary..."
	Set-NsxManagerRole Primary -WarningAction SilentlyContinue
	
	# Step 2
	My-Logger "Deploying NSX Controllers..."
			
		 try {
		 
			$cluster = Get-Cluster -Name $ControllerCluster -errorAction Stop
			$datastore = Get-Datastore -Name $ControllerDatastore -errorAction Stop
			$PortGroup = Get-VdPortGroup $ControllerNetworkPortGroupName -errorAction Stop
			
			$ControllerPool = Get-NsxIpPool -Name "ControllerPool"
			
			if(!$ControllerPool){		 
				My-Logger "   -> Creating IP Pool for Controller addressing"
				$ControllerPool = New-NsxIpPool -Name "ControllerPool" -Gateway $ControllerNetworkGateway -SubnetPrefixLength $ControllerNetworkSubnetPrefixLength -StartAddress $ControllerPoolStartIp -EndAddress $ControllerPoolEndIp 
			}
			
				for ( $i=1; $i -le 3; $i++ ) {

					My-Logger "   -> Deploying NSX Controller $($i)"

					$Controller = New-NsxController -IpPool $ControllerPool -Cluster $cluster -datastore $datastore -PortGroup $PortGroup  -password $ControllerPassword -confirm:$false -wait
			 
					My-Logger "   -> Controller $($i) online."
				}
			}
			
			catch {
			My-Logger "Failed deploying controller Cluster.  $_"
			Throw  "Failed deploying controller Cluster.  $_"
			}
		
	
	# Step 3
	My-Logger  "Update Controller State.."
	$apistr="/api/2.0/vdn/controller/synchronize"
	 
	Invoke-NsxRestMethod -Method put -Uri $apistr -InformationAction:SilentlyContinue

	# Step 4
	My-Logger  "Deploying UDLR CVMs.."
		
	$clusterMoRef = $cluster.Id
	$datastoreMoref = $datastore.Id
	
	$clusterMoRef=$clusterMoRef.Replace("ClusterComputeResource-","")
	$datastoreMoref=$datastoreMoref.Replace("Datastore-","")
		
	$UDLR = Get-NsxLogicalRouter -name $UDLR1Name
		
	$UDLRid = $UDLR.id
	$apistr="/api/4.0/edges/$UDLRid"
	$UDLRXML=Invoke-NsxRestMethod  -Method get -Uri $apistr
	
	$appliances=$UDLRXML.SelectSingleNode("//appliances")
	$child = $UDLRXML.CreateElement("appliance")
	$appliances.AppendChild($child)
	
	$appliances=$UDLRXML.SelectSingleNode("//appliance")
	$child = $UDLRXML.CreateElement("datastoreId")
	$appliances.AppendChild($child) 
	
	$child = $UDLRXML.CreateElement("resourcePoolId")
	$appliances.AppendChild($child) 
		
	$element = $UDLRXML.SelectSingleNode("//datastoreId")
	$element.InnerText =$datastoreMoref
	
	$element = $UDLRXML.SelectSingleNode("//resourcePoolId")
	$element.InnerText =$clusterMoRef
			
	$UDLRXML.Save($UDLRid+".xml")
	$body=$UDLRXML.OuterXml
	Invoke-NsxRestMethod  -Method put -Uri $apistr -body $body | out-null

	$EndTime = Get-Date
	$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)

	My-Logger  "Duration: $duration minutes"

	Disconnect-VIServer -Server $VIServer -confirm:$false | out-null
	Disconnect-NsxServer
