<# 
    NSX-v Deployment for voLTE Onboarding
	Created by Hakan Akkurt
	https://www.linkedin.com/in/hakkurt/
	December 2018
    	
	Script Functionalities
	
	- Create VDS portgroups for ESG Uplink interfaces
	- Configure VDS portgroup(LACP and teaming)
	- Create VNF Logical Switches
	- Create UDLR 
	- Create UDLR LIFs for VNFs
	- Create ESGs for IPv4 networks
	- Create Anti-affinity rules for ESGs 
	- Configure routing on ESG and UDLR(BGP)
	- Configure route redistribution
	- Configure floating static routes on ESGs
	- Enable ECMP, Disable Graceful Restart and RFP
	- Disable firewall on ECMP enabled ESGs and DLR
	- Set Syslog for all components
#>

$ScriptVersion = "1.3"
$global:DCPrefix = "DC1"
$global:VNFPrefix = "VOLTE"

# vCenter Configuration
$VIServer = "vcsa-01a.corp.local"
$PSCServer = "vcsa-01a.corp.local"
$VIUsername = "administrator@vsphere.local"
$VIPassword = "VMware1!"

# NSX Configuration
$NSXHostname = "nsxmgr-01a.corp.local"
$NSXUIPassword = "VMware1!"

$global:EdgeDatastore1 = "RegionA01-ISCSI01-COMP01"
$global:EdgeDatastore2 = "RegionA01-ISCSI01-COMP01"
$global:EdgeDatastore3 = "RegionA01-ISCSI01-COMP01"
$global:EdgeCluster = "RegionA01-MGMT01"
$global:EdgeVDS = "RegionA01-vDS-MGMT"
$global:ESGDefaultSubnetBits = "29" 
$global:ESGFormFactor = "compact" # use xlarge for Prod

$global:DLRDatastore = "RegionA01-ISCSI01-COMP01"
$global:DLRCluster = "RegionA01-MGMT01"
$global:TransportZoneName = "UTZ"
$global:DLRDefaultSubnetBits = "28" 

$global:AppliancePassword = "VMware1!VMware1!"
$global:iBGPAS = "65033" 
$global:eBGPAS = "64700"
$global:BGPKeepAliveTimer = "1"
$global:BGPHoldDownTimer = "3"

$global:sysLogServer = "192.168.1.165"
$global:sysLogServerPort = "514"

# Static Deployment Parameters
$verboseLogFile = "ScriptLogs.log"


	Function My-Logger {
		param(
		[Parameter(Mandatory=$true)]
		[String]$message,
		[String]$color
		
		)
		
		$timeStamp = Get-Date -Format "MM-dd-yyyy_hh:mm:ss"

		Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
		Write-Host -ForegroundColor $color " $message"
		$logMessage = "[$timeStamp] $message"
		$logMessage | Out-File -Append -LiteralPath $verboseLogFile
	}

	$banner = @"
| | / / |/ / __/ / __ \___  / /  ___  ___ ________/ (_)__  ___ _
| |/ /    / _/  / /_/ / _ \/ _ \/ _ \/ _ `/ __/ _  / / _ \/ _ `/
|___/_/|_/_/    \____/_//_/_.__/\___/\_,_/_/  \_,_/_/_//_/\_, / 
                                                         /___/  
"@

	Write-Host -ForegroundColor magenta $banner 
	Write-Host -ForegroundColor magenta "Starting NSX VNF Deploy Script version $ScriptVersion"

	# Check PowerCli and PowerNSX modules

	My-Logger "Checking PowerCli and PowerNSX Modules ..." "Yellow"
	
	$PSVersion=$PSVersionTable.PSVersion.Major
	
	# If you manually install PowerCLI and PowerNSX, you can remove this part
	if($PSVersion -le 4) {
		Write-Host -ForegroundColor red "You're using older version of Powershell. Please upgrade your Powershell from following URL :"
		Write-Host -ForegroundColor red "https://www.microsoft.com/en-us/download/details.aspx?id=54616"
		exit
	}
	
	Find-Module VMware.PowerCLI | Install-Module -Scope CurrentUser -Confirm:$False
	Find-Module PowerNSX | Install-Module -Scope CurrentUser -Confirm:$False

	Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -confirm:$false | out-null
	Set-PowerCLIConfiguration -invalidcertificateaction Ignore -confirm:$false | out-null
	Set-PowerCLIConfiguration -Scope Session -WebOperationTimeoutSeconds 3600 -confirm:$false | out-null
	
	My-Logger "PowerCli and PowerNSX Modules check completed..." "green"
	
	$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue
		
	try {
	 
		My-Logger "-> Connecting NSX Manager..." "White" 
	 
			if(!(Connect-NSXServer -Server $NSXHostname -Username admin -Password $NSXUIPassword -DisableVIAutoConnect -WarningAction SilentlyContinue)) {
				My-Logger "Unable to connect to NSX Manager, please check the deployment" "Red"
				exit
			} else {
				My-Logger "Successfully logged into NSX Manager $NSXHostname" "white"			
			}
	
	}
	
	catch {
		Throw  "Error while connecting NSX Manager"
	}  
	
	Function BuildNSXforVNF {
    param(
    [String]$VRFName,
	[String]$ESG1UplinkVLAN,
	[String]$ESG1UplinkAddress,
	[String]$ESG1DownlinkAddress,
	[String]$ESG1NeighborIPAddress1,
	[String]$ESG1NeighborIPAddress2,
	[String]$ESG2UplinkVLAN,
	[String]$ESG2UplinkAddress,
	[String]$ESG2DownlinkAddress,
	[String]$ESG2NeighborIPAddress1,
	[String]$ESG2NeighborIPAddress2,
	[String]$DLRForwardingIPAddress,
	[String]$DLRProtocolIPAddress,
	[String]$EdgeDatastore,
	[collections.arraylist]$VNFExternalNetworks
		
    )
		$ESGDataStore = Get-Datastore -Name $EdgeDatastore -errorAction Stop
		$DLRDataStore = Get-Datastore -Name $global:DLRDatastore -errorAction Stop
		$DLRCluster = Get-Cluster -Name $global:DLRCluster -errorAction Stop
		$ESGCluster = Get-Cluster -Name $global:EdgeCluster -errorAction Stop
		
		# Logical Switches / Routers / VDS Portgroup Names
		# e.g. DC1_TRANSIT_VOLTE_BILL, DC1_DLRHA_VOLTE_LIN
		$TransitLsName = $global:DCPrefix +"_TRANSIT_"+$global:VNFPrefix+"_"+$VRFName 
		$EdgeHALsName = $global:DCPrefix+"_DLRHA_"+$global:VNFPrefix+"_"+$VRFName
		# e.g. DC1-ESG-VOLTE-SIGTRAN1-1
		$ESG1Name = $global:DCPrefix+"-ESG-"+$global:VNFPrefix+"-"+$VRFName+"-1" 
		$ESG2Name = $global:DCPrefix+"-ESG-"+$global:VNFPrefix+"-"+$VRFName+"-2" 
		# e.g. DC1-UDLR-VOLTE-OUM 		
		$UDLRName = $global:DCPrefix+"-UDLR-"+$global:VNFPrefix+"-"+$VRFName 
		# DC1_ESG_VOLTE_CONTROL_1_ACI
		$ESG1UplinkName = $global:DCPrefix+"_ESG_"+$global:VNFPrefix+"_"+$VRFName+"_1_ACI"
		$ESG2UplinkName = $global:DCPrefix+"_ESG_"+$global:VNFPrefix+"_"+$VRFName+"_2_ACI"
		
		$activePortsList = "Uplink 3"
		$UnusedUplinkPort = "Uplink 1", "Uplink 2"
		
		My-Logger "--- Deployment and configuration of NSX Environment for $VRFName is started --- " "Blue"
		
		My-Logger "Creating VDS Port groups for ESG uplinks ..." "Green"

			if (Get-VDPortGroup -Name $ESG1UplinkName -VDSwitch $global:EdgeVDS -ErrorAction SilentlyContinue) {
				My-Logger "$ESG1UplinkName is already exist..." "Yellow"
				$ESG1Uplink = Get-VDPortGroup -Name $ESG1UplinkName -VDSwitch $global:EdgeVDS
			}
			else {
				$ESG1Uplink = Get-VDSwitch -Name $global:EdgeVDS | New-VDPortgroup -Name $ESG1UplinkName -VLanId $ESG1UplinkVLAN 
				My-Logger "Setting Teaming for $ESG1UplinkName ..." "Green"
				Get-VDSwitch $global:EdgeVDS | Get-VDPortgroup $ESG1UplinkName | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -ActiveUplinkPort $activePortsList -UnusedUplinkPort $UnusedUplinkPort |out-null
			}
				
			if (Get-VDPortGroup -Name $ESG2UplinkName -VDSwitch $global:EdgeVDS -ErrorAction SilentlyContinue) {
				My-Logger "$ESG2UplinkName is already exist..." "Yellow"
				$ESG2Uplink = Get-VDPortGroup -Name $ESG2UplinkName -VDSwitch $global:EdgeVDS
			}
			else {
				$ESG2Uplink = Get-VDSwitch -Name $global:EdgeVDS | New-VDPortgroup -Name $ESG2UplinkName -VLanId $ESG2UplinkVLAN 
				My-Logger "Setting Teaming for $ESG2UplinkName ..." "Green"
				Get-VDSwitch $global:EdgeVDS | Get-VDPortgroup $ESG2UplinkName | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -ActiveUplinkPort $activePortsList -UnusedUplinkPort $UnusedUplinkPort |out-null

			}				
		
		My-Logger "Creating Logical Switches for $VRFName ..." "Green"
	 
			 foreach ($item in  $VNFExternalNetworks)  {
				$LSName =$item[0]
					if (Get-NsxLogicalSwitch $LSName) {
						My-Logger "$LSName is already exist..." "Yellow"
					}
					else {
						Get-NsxTransportZone -name $global:TransportZoneName | New-NsxLogicalSwitch $LSName |out-null
					}
			}

			if (Get-NsxLogicalSwitch $TransitLsName) {
				$TransitLs = Get-NsxLogicalSwitch $TransitLsName   
				My-Logger "$TransitLsName is already exist..." "Yellow"						
			}
			else {
				$TransitLs = Get-NsxTransportZone -name $global:TransportZoneName | New-NsxLogicalSwitch $TransitLsName 
			}
			if (Get-NsxLogicalSwitch $EdgeHALsName) {
			
				$MgmtLs = Get-NsxLogicalSwitch $EdgeHALsName   
				My-Logger "$EdgeHALsName is already exist..." "Yellow"	
			}
			else {
				$MgmtLs = Get-NsxTransportZone -name $global:TransportZoneName | New-NsxLogicalSwitch $EdgeHALsName
			}
		
		### UDLR ###
	
		$Ldr = Get-NsxLogicalRouter -Name "$UDLRName" -ErrorAction silentlycontinue
			
			if(!$Ldr){
			
				# DLR Appliance has the uplink router interface created first.
				My-Logger "Creating DLR $UDLRName" "Green"
				$LdrvNic0 = New-NsxLogicalRouterInterfaceSpec -type Uplink -Name $TransitLsName -ConnectedTo $TransitLs -PrimaryAddress $DLRForwardingIPAddress -SubnetPrefixLength $global:DLRDefaultSubnetBits
			
				# HA will be enabled			
					
				My-Logger "Enabling HA for $UDLRName" "Green"
				# The DLR is created with the first vnic defined, and the datastore and cluster on which the Control VM will be deployed.
				$Ldr = New-NsxLogicalRouter -name $UDLRName -interface $LdrvNic0 -ManagementPortGroup $MgmtLs -Cluster $DLRCluster -datastore $DLRDataStore -EnableHA  -Universal 
				
				# Create DLR Internal Interfaces
				My-Logger "Creating VNF LIFs on $UDLRName" "Green"
				
				$Ldr = Get-NsxLogicalRouter  -name $UDLRName
				foreach ($item in  $VNFExternalNetworks)  {
				
					$LSName =$item[0]
					$DLRLIFIP = $item[1]
					$VNFLs = Get-NsxLogicalSwitch $LSName
					$ldr | New-NsxLogicalRouterInterface -Name $LSName -Type internal -ConnectedTo $VNFLs -PrimaryAddress $DLRLIFIP -SubnetPrefixLength $global:DLRDefaultSubnetBits | out-null
				}
				
				# Set DLR Password via XML Element
				$Ldr = Get-NsxLogicalRouter  -name $UDLRName

				Add-XmlElement -xmlRoot $Ldr.CliSettings -xmlElementName "password" -xmlElementText $global:AppliancePassword 
				$ldr | Set-NsxLogicalRouter -confirm:$false | out-null
				
				# Change DLR Name
				My-Logger "DLR Hostname is setting ..." "Green"
				$Ldr = Get-NsxLogicalRouter  -name $UDLRName
				$Ldr.fqdn="$UDLRName"
				$ldr | Set-NsxLogicalRouter -confirm:$false | out-null

					## Enable DLR Syslog
				
					if ($global:sysLogServer) {
					
						My-Logger "Setting Syslog server for $UDLRName" "Green"
						$Ldr = get-nsxlogicalrouter $UDLRName
						$LdrID = $Ldr.id
							
						$apistr="/api/4.0/edges/$LdrID/syslog/config"
						$body="<syslog>
						<enabled>true</enabled>
						<protocol>udp</protocol>
						<serverAddresses>
						<ipAddress>$global:sysLogServer</ipAddress>
						</serverAddresses>
						</syslog>"

						Invoke-NsxRestMethod  -Method put -Uri $apistr -body $body | out-null
					}
					
				## Disable DLR firewall
				My-Logger "Disabling DLR Firewall..." "Green"
				$Ldr = get-nsxlogicalrouter $UDLRName
				$Ldr.features.firewall.enabled = "false"
				$Ldr | Set-nsxlogicalrouter -confirm:$false | out-null

			}
		
		# EDGE

		$Edge1 = Get-NsxEdge -name $ESG1Name
			
			if(!$Edge1) {
			
				## Defining the uplink and internal interfaces to be used when deploying the edge. Note there are two IP addresses on these interfaces. $EdgeInternalSecondaryAddress and $EdgeUplinkSecondaryAddress are the VIPs
				$edgevnic0 = New-NsxEdgeinterfacespec -index 0 -Name $ESG1UplinkName -type Uplink -ConnectedTo $ESG1Uplink -PrimaryAddress $ESG1UplinkAddress -SubnetPrefixLength $global:ESGDefaultSubnetBits
				$edgevnic1 = New-NsxEdgeinterfacespec -index 1 -Name $TransitLsName -type Internal -ConnectedTo $TransitLs -PrimaryAddress $ESG1DownlinkAddress -SubnetPrefixLength $global:DLRDefaultSubnetBits

				## Deploy appliance with the defined uplinks (-FormFactor xlarge for Prod)
				My-Logger "Creating Edge $ESG1Name" "Green"
				
				$Edge1 = New-NsxEdge -name $ESG1Name -hostname $ESG1Name -cluster $ESGCluster -datastore $ESGDataStore -Interface $edgevnic0, $edgevnic1 -Password $global:AppliancePassword -FwEnabled:$false -FormFactor $global:ESGFormFactor -enablessh
									
				# Disabling Reverse Path Forwarding (RPF) for $ESG1Name  ...
				$Edge1 = Get-NsxEdge -name $ESG1Name			
				$Edge1Id=$Edge1.id
				
				$apistr="/api/4.0/edges/$Edge1Id/systemcontrol/config"
				$body="<systemControl>
				<property>sysctl.net.ipv4.conf.all.rp_filter=0</property>
				<property>sysctl.net.ipv4.conf.vNic_0.rp_filter=0</property>
				<property>sysctl.net.ipv4.conf.vNic_1.rp_filter=0</property>
				</systemControl>"

				Invoke-NsxRestMethod  -Method put -Uri $apistr -body $body | out-null
				
				## Enable Syslog
					if ($global:sysLogServer ) {
				
						My-Logger "Setting syslog server for $ESG1Name" "Green"
						
						$Edge1 = get-NSXEdge -name $ESG1Name
						$Edge1Id=$Edge1.id
							
						$apistr="/api/4.0/edges/$Edge1Id/syslog/config"
						$body="<syslog>
						<enabled>true</enabled>
						<protocol>udp</protocol>
						<serverAddresses>
						<ipAddress>$global:sysLogServer</ipAddress>
						</serverAddresses>
						</syslog>"

						Invoke-NsxRestMethod  -Method put -Uri $apistr -body $body | out-null
					}
					
			 }
		 
					 
		$Edge2 = Get-NsxEdge -name $ESG2Name
			
			if(!$Edge2) {
			
				## Defining the uplink and internal interfaces to be used when deploying the edge. Note there are two IP addreses on these interfaces. $EdgeInternalSecondaryAddress and $EdgeUplinkSecondaryAddress are the VIPs
				$edgevnic0 = New-NsxEdgeinterfacespec -index 0 -Name $ESG2UplinkName -type Uplink -ConnectedTo $ESG2Uplink -PrimaryAddress $ESG2UplinkAddress -SubnetPrefixLength $global:ESGDefaultSubnetBits
				$edgevnic1 = New-NsxEdgeinterfacespec -index 1 -Name $TransitLsName -type Internal -ConnectedTo $TransitLs -PrimaryAddress $ESG2DownlinkAddress -SubnetPrefixLength $global:DLRDefaultSubnetBits
		
				## Deploy appliance with the defined uplinks (-FormFactor xlarge for Prod)
				My-Logger "Creating Edge $ESG2Name" "Green" 
				$Edge2 = New-NsxEdge -name $ESG2Name -hostname $ESG2Name -cluster $ESGCluster -datastore $ESGDataStore -Interface $edgevnic0, $edgevnic1 -Password $global:AppliancePassword -FwEnabled:$false -FormFactor $global:ESGFormFactor  -enablessh
				
				# Disabling Reverse Path Forwarding (RPF) for $ESG2Name  ...
				$Edge2 = Get-NsxEdge -name $ESG2Name			
				$Edge2Id=$Edge2.id
				
				$apistr="/api/4.0/edges/$Edge2Id/systemcontrol/config"
				$body="<systemControl>
				<property>sysctl.net.ipv4.conf.all.rp_filter=0</property>
				<property>sysctl.net.ipv4.conf.vNic_0.rp_filter=0</property>
				<property>sysctl.net.ipv4.conf.vNic_1.rp_filter=0</property>
				</systemControl>"

				Invoke-NsxRestMethod  -Method put -Uri $apistr -body $body | out-null
				
				## Enable Syslog
					if ($global:sysLogServer ) {
			
						My-Logger "Setting syslog server for $ESG2Name" "Green"
						$Edge2 = Get-NSXEdge -name $ESG2Name
						$Edge2Id=$Edge2.id
							
						$apistr="/api/4.0/edges/$Edge2Id/syslog/config"
						$body="<syslog>
						 <enabled>true</enabled>
						<protocol>udp</protocol>
						<serverAddresses>
						<ipAddress>$global:sysLogServer</ipAddress>
						</serverAddresses>
						</syslog>"

						Invoke-NsxRestMethod  -Method put -Uri $apistr -body $body | out-null
					}
				
			 }
			
		
		#####################################
		# BGP #
		if($Edge1) {
			My-Logger "Configuring BGP on $ESG1Name" "green"		
			$rtg = Get-NsxEdge $ESG1Name | Get-NsxEdgeRouting
			$rtg | Set-NsxEdgeRouting -EnableEcmp -EnableBgp -RouterId $ESG1UplinkAddress -LocalAS $global:iBGPAS -Confirm:$false | out-null

			$rtg = Get-NsxEdge $ESG1Name | Get-NsxEdgeRouting			
			$rtg | New-NsxEdgeBgpNeighbour -IpAddress $DLRProtocolIPAddress -RemoteAS $global:iBGPAS -KeepAliveTimer $global:BGPKeepAliveTimer -HoldDownTimer $global:BGPHoldDownTimer  -confirm:$false | out-null
			$rtg = Get-NsxEdge $ESG1Name | Get-NsxEdgeRouting	
			$rtg | New-NsxEdgeBgpNeighbour -IpAddress $ESG1NeighborIPAddress1 -RemoteAS $global:eBGPAS -KeepAliveTimer $global:BGPKeepAliveTimer -HoldDownTimer $global:BGPHoldDownTimer  -confirm:$false | out-null
			$rtg = Get-NsxEdge $ESG1Name | Get-NsxEdgeRouting	
			$rtg | New-NsxEdgeBgpNeighbour -IpAddress $ESG1NeighborIPAddress2 -RemoteAS $global:eBGPAS -KeepAliveTimer $global:BGPKeepAliveTimer -HoldDownTimer $global:BGPHoldDownTimer  -confirm:$false | out-null
			
			$rtg = Get-NsxEdge $ESG1Name | Get-NsxEdgeRouting		
			$rtg | Set-NsxEdgeBgp -GracefulRestart:$false -Confirm:$false | out-null
			
			My-Logger "Configuring $ESG1Name floating static routes" "green"
				
				foreach ($item in  $VNFExternalNetworks)  {
					
						$DLRLIFIP = $item[1]
						$DLRLIFSubnet=[IPAddress] (([IPAddress] $DLRLIFIP).Address -band ([IPAddress] "255.255.255.240").Address)
						
						$DLRVNFStaticRoute = $DLRLIFSubnet.IPAddressToString +"/"+$global:DLRDefaultSubnetBits
						Get-NsxEdge $ESG1Name | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network $DLRVNFStaticRoute -NextHop $DLRForwardingIPAddress -AdminDistance 240 -confirm:$false | out-null
				}
			Get-NsxEdge $ESG1Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableOspfRouteRedistribution:$false -confirm:$false | out-null
			Get-NsxEdge $ESG1Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableBgpRouteRedistribution:$true -confirm:$false | out-null
			Get-NsxEdge $ESG1Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -Learner ospf | Remove-NsxEdgeRedistributionRule -Confirm:$false | out-null
			Get-NsxEdge $ESG1Name | Get-NsxEdgeRouting | New-NsxEdgeRedistributionRule -Learner bgp -FromConnected -FromStatic -Action permit -confirm:$false | out-null
			
		}
		
		if($Edge2) {		
			My-Logger "Configuring BGP on $ESG2Name" "green"
			$rtg = Get-NsxEdge $ESG2Name | Get-NsxEdgeRouting
			$rtg | Set-NsxEdgeRouting -EnableEcmp -EnableBgp -RouterId $ESG2UplinkAddress -LocalAS $global:iBGPAS -Confirm:$false | out-null
			
			$rtg = Get-NsxEdge $ESG2Name | Get-NsxEdgeRouting
			$rtg | New-NsxEdgeBgpNeighbour -IpAddress $DLRProtocolIPAddress -RemoteAS $global:iBGPAS -KeepAliveTimer $global:BGPKeepAliveTimer -HoldDownTimer $global:BGPHoldDownTimer  -confirm:$false | out-null
			$rtg = Get-NsxEdge $ESG2Name | Get-NsxEdgeRouting
			$rtg | New-NsxEdgeBgpNeighbour -IpAddress $ESG2NeighborIPAddress1 -RemoteAS $global:eBGPAS -KeepAliveTimer $global:BGPKeepAliveTimer -HoldDownTimer $global:BGPHoldDownTimer  -confirm:$false | out-null
			$rtg = Get-NsxEdge $ESG2Name | Get-NsxEdgeRouting
			$rtg | New-NsxEdgeBgpNeighbour -IpAddress $ESG2NeighborIPAddress2 -RemoteAS $global:eBGPAS -KeepAliveTimer $global:BGPKeepAliveTimer -HoldDownTimer $global:BGPHoldDownTimer  -confirm:$false | out-null
						
			$rtg = Get-NsxEdge $ESG2Name | Get-NsxEdgeRouting
			$rtg | Set-NsxEdgeBgp -GracefulRestart:$false -Confirm:$false | out-null
			
				foreach ($item in  $VNFExternalNetworks)  {
					
						$DLRLIFIP = $item[1]
						$DLRLIFSubnet=[IPAddress] (([IPAddress] $DLRLIFIP).Address -band ([IPAddress] "255.255.255.240").Address)
						
						$DLRVNFStaticRoute = $DLRLIFSubnet.IPAddressToString +"/"+$global:DLRDefaultSubnetBits
						Get-NsxEdge $ESG2Name | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network $DLRVNFStaticRoute -NextHop $DLRForwardingIPAddress -AdminDistance 240 -confirm:$false | out-null
				}
		 
		 	Get-NsxEdge $ESG2Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableOspfRouteRedistribution:$false -confirm:$false | out-null
			Get-NsxEdge $ESG2Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableBgpRouteRedistribution:$true -confirm:$false | out-null
			Get-NsxEdge $ESG2Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -Learner ospf | Remove-NsxEdgeRedistributionRule -Confirm:$false | out-null
			Get-NsxEdge $ESG2Name | Get-NsxEdgeRouting | New-NsxEdgeRedistributionRule -Learner bgp -FromConnected -FromStatic -Action permit -confirm:$false | out-null
				
		}
		
		if($Ldr){
			My-Logger "Configuring BGP on $UDLRName" "green"
			
			Get-NsxLogicalRouter $UDLRName | Get-NsxLogicalRouterRouting | set-NsxLogicalRouterRouting -EnableEcmp -EnableBgp -RouterId $DLRForwardingIPAddress -LocalAS $global:iBGPAS -ProtocolAddress $DLRProtocolIPAddress -ForwardingAddress $DLRForwardingIPAddress -confirm:$false | out-null
			Get-NsxLogicalRouter $UDLRName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterBgpNeighbour -IpAddress $ESG1DownlinkAddress -RemoteAS $global:iBGPAS -ProtocolAddress $DLRProtocolIPAddress -ForwardingAddress $DLRForwardingIPAddress  -KeepAliveTimer $global:BGPKeepAliveTimer -HoldDownTimer $global:BGPHoldDownTimer -confirm:$false | out-null
			Get-NsxLogicalRouter $UDLRName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterBgpNeighbour -IpAddress $ESG2DownlinkAddress -RemoteAS $global:iBGPAS -ProtocolAddress $DLRProtocolIPAddress -ForwardingAddress $DLRForwardingIPAddress  -KeepAliveTimer $global:BGPKeepAliveTimer -HoldDownTimer $global:BGPHoldDownTimer -confirm:$false | out-null
		
			My-Logger "Configuring Route Redistribution" "green"
			Get-NsxLogicalRouter $UDLRName | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableOspfRouteRedistribution:$false -confirm:$false | out-null
			Get-NsxLogicalRouter $UDLRName | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableBgpRouteRedistribution:$true -confirm:$false | out-null
			Get-NsxLogicalRouter $UDLRName | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule -Learner ospf | Remove-NsxLogicalRouterRedistributionRule -Confirm:$false | out-null
			Get-NsxLogicalRouter $UDLRName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterRedistributionRule -Learner bgp -FromConnected -Action permit -confirm:$false | out-null
			
			My-Logger "Disabling Graceful Restart" "green"
			$rtg = Get-NsxLogicalRouter $UDLRName | Get-NsxLogicalRouterRouting
			$rtg | Set-NsxLogicalRouterBgp -GracefulRestart:$false -confirm:$false | out-null
		}
			
			<# My-Logger "Creating Anti Affinity Rules for ESGs" "Green"
				$antiAffinityVMs=Get-VM | Where {$_.name -like "$ESG1Name*" -or $_.name -like "$ESG2Name*"}
				New-DrsRule -Cluster $VMCluster -Name SeperateESGs -KeepTogether $false -VM $antiAffinityVMs | out-null #>
			
			My-Logger "--- Deployment and configuration of NSX Environment for $VRFName is completed --- " "Blue"
	  
	}

	$StartTime = Get-Date
	
	# Create OUM Topology 
	$VRFName="OUM"
	$ESG1UplinkVLAN="1750"
	$ESG1UplinkAddress= "172.145.54.6"
	$ESG1DownlinkAddress="172.145.54.17"
	$ESG1NeighborIPAddress1="172.145.54.1"
	$ESG1NeighborIPAddress2="172.145.54.2"
	$ESG2UplinkVLAN="1751"
	$ESG2UplinkAddress="172.145.54.14"
	$ESG2DownlinkAddress="172.145.54.18"
	$ESG2NeighborIPAddress1="172.145.54.9"
	$ESG2NeighborIPAddress2="172.145.54.10"
	$DLRForwardingIPAddress="172.145.54.29"
	$DLRProtocolIPAddress="172.145.54.30"
	$EdgeDatastore =$global:EdgeDatastore1
	$VNFExternalNetworks = @(("DC1_DLE_VOLTE_OUM_TAS-1","172.145.56.1"),("DC1_DLE_VOLTE_OUM_TAS-2","172.145.56.17"),("DC1_DLE_VOLTE_OUM_CFX-1","172.145.56.33"),("DC1_DLE_VOLTE_OUM_CFX-2","172.145.56.49"),("DC1_DLE_VOLTE_OUM_EIMS","172.145.56.161"),("DC1_DLE_VOLTE_OUM_CMREPO","172.145.56.177"),("DC1_DLE_VOLTE_OUM_ASBC-1","172.145.56.65"),("DC1_DLE_VOLTE_OUM_ASBC-2","172.145.56.81"))
	
	BuildNSXforVNF $VRFName $ESG1UplinkVLAN $ESG1UplinkAddress $ESG1DownlinkAddress $ESG1NeighborIPAddress1	$ESG1NeighborIPAddress2 $ESG2UplinkVLAN $ESG2UplinkAddress 	$ESG2DownlinkAddress $ESG2NeighborIPAddress1 $ESG2NeighborIPAddress2 $DLRForwardingIPAddress $DLRProtocolIPAddress $EdgeDatastore $VNFExternalNetworks	
	
	My-Logger "NSX Configuration for VOLTE is completed" "white"
	$EndTime = Get-Date
	$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)
	write-host "Duration: $duration minutes"
	

Disconnect-VIServer $viConnection -Confirm:$false
Disconnect-NsxServer