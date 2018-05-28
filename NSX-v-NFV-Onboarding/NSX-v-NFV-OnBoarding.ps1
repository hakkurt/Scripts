<# 
    NSX Deployment for NFV Onboarding
	Created by Hakan Akkurt
	https://www.linkedin.com/in/hakkurt/
	April 2018
    	
	Script Functionalities
	
	- Create VNF Logical Switches
	- Create DLR or UDLR based on selected option
	- Create DLR LIFs for VNFs
	- Create ESGs for IPv4 networks (HA or ECMP mode)
	- Create ESG for IPv6 networks
	- Create Anti-affinity rules for ESGs (for ECMP mode)
	- Configure routing based on ESG model(static or BGP)
	- Configure route redistribution
	- Configure floating static routes on ESGs
	- Enable ECMP, Disable Graceful Restart and RFP
	- Set Syslog for all components
	
#>

$ScriptVersion = "1.2"
$VNFPrefix = "VoLTE"
$VNFDesc = "Nokia VoLTE"
$VRFPrefix = "SIGTRAN1"

# Deployment Parameters
$DeploymentIPModel = "IPv6" # Select IPv4 or IPv6
$DeploymentNSXModel = "Local" # Select Local or Universal
$verboseLogFile = "ScriptLogs.log"

# vCenter Configuration
$VIServer = "vcsa-01a.corp.local"
$PSCServer = "vcsa-01a.corp.local"
$VIUsername = "administrator@vsphere.local"
$VIPassword = "VMware1!"

# NSX Configuration
$NSXHostname = "nsxmgr-01a.corp.local"
$NSXUIPassword = "VMware1!"
$VMDatastore = "RegionA01-ISCSI01-COMP01"
$VMCluster = "RegionA01-MGMT01"
$EdgeUplinkNetworkName = "voLTE-SIGTRAN1-ESGToPhysical"
$EdgeUplinkNetworkNameIPv6 = "voLTE-SIGTRAN1-ESGToPhysical-IPv6"
$TransportZoneName = "RegionA0-Global-TZ"

# Logical Switches / Router Names 
# e.g. LS-voLTE-SIGTRAN1-Transit
$TransitLsName = "LS-"+$VNFPrefix+"-"+$VRFPrefix+"-Transit" 
$EdgeHALsName = "LS-"+$VNFPrefix+"-"+$VRFPrefix+"-HA" 
$PLR01Name = "ESG-"+$VNFPrefix+"-"+$VRFPrefix+"-01" 
$PLR02Name = "ESG-"+$VNFPrefix+"-"+$VRFPrefix+"-02"  
$DLRName = "DLR-"+$VNFPrefix+"-"+$VRFPrefix+"-01" 
$UDLRName = "UDLR-"+$VNFPrefix+"-"+$VRFPrefix+"-01" 

#Get-Random -Maximum 100 - Can be used for Object name creation


# IPv4 Routing Topology 
$PLR01InternalAddress = "40.40.40.3" 
$PLR01UplinkAddress = "10.10.20.2" 
$PLR01Size = "Compact"
$PLR02InternalAddress = "40.40.40.4" 
$PLR02UplinkAddress = "10.10.20.3" 
$PLR02Size = "Compact"
$PLReBGPNeigbour1 ="10.10.20.1"
$DLRUplinkAddress = "40.40.40.1"
$DLR01ProtocolAddress = "40.40.40.2" 

# VNF External Networks 
$VNFExternalNetworks = (("LS-voLTE-SIGTRAN1-TAS-01","172.16.100.1"),("LS-voLTE-SIGTRAN1-CFX-01","172.16.110.1"),("LS-voLTE-SIGTRAN1-SBC-01","172.16.120.1"))
$DefaultSubnetMask = "255.255.255.0" 
$DefaultSubnetBits = "24" 
$AppliancePassword = "VMware1!VMware1!"
$RoutingProtocol = "BGP" # Select BGP or Static
$PLRMode = "ECMP" # Select ECMP or HA
$iBGPAS = "65033" 
$eBGPAS = "1"
$BGPKeepAliveTimer = "1"
$BGPHoldDownTimer = "4"

# IPv6 Networks 
$EdgeHALsNameIPv6 = "LS-"+$VNFPrefix+"-"+$VRFPrefix+"-IPv6-HA"
$VNFNetworkLsNameIPv6 = "LS-"+$VNFPrefix+"-"+$VRFPrefix+"-IPv6" 
$PLRNameIPv6 = "ESG-"+$VNFPrefix+"-"+$VRFPrefix+"-IPv6-01" 
$PLRInternalAddressIPv6 = "2a01:8f0:600:2::1" 
$PLRUplinkAddressIPv6 = "2a01:8f0:400:15::2"
$PLRDefaultGWIPv6 = "2a01:8f0:400:15::1"
$IPv6Prefix = "64"

# Parameter initial values
$domainname = $null
$sysLogServer = "192.168.1.165"
$sysLogServerName = $null
$sysLogServerPort = "514"

$WaitStep = 30
$WaitTimeout = 600

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
	
	$StartTime = Get-Date
	
	$cluster = Get-Cluster -Name $VMCluster -errorAction Stop		
	$datastore = Get-Datastore -Name $VMDatastore -errorAction Stop
	
	if($DeploymentIPModel -eq "IPv4"){	
		
		###################################### 
		#Logical Switches 
	 
		# Creates logical switches 
	
		 My-Logger "Creating Logical Switches..." "Green"
	 
			 foreach ($item in  $VNFExternalNetworks)  {
				$LSName =$item[0]
					
					if (Get-NsxLogicalSwitch $LSName) {
						My-Logger "$LSName is already exist..." "Yellow"
					}
					else {
						Get-NsxTransportZone -name $TransportZoneName | New-NsxLogicalSwitch $LSName |out-null
					}
			}

			if (Get-NsxLogicalSwitch $TransitLsName) {
				$TransitLs = Get-NsxLogicalSwitch $TransitLsName   
				My-Logger "$TransitLsName is already exist..." "Yellow"						
			}
			else {
				$TransitLs = Get-NsxTransportZone -name $TransportZoneName | New-NsxLogicalSwitch $TransitLsName |out-null
			}
			if (Get-NsxLogicalSwitch $EdgeHALsName) {
			
				$MgmtLs = Get-NsxLogicalSwitch $EdgeHALsName   
				My-Logger "$EdgeHALsName is already exist..." "Yellow"	
							
			}
			else {
				$MgmtLs = Get-NsxTransportZone -name $TransportZoneName | New-NsxLogicalSwitch $EdgeHALsName |out-null
			}

		######################################
		# DLR
		
		if($DeploymentNSXModel -eq "Local"){
		
			$Ldr = Get-NsxLogicalRouter -Name "$DLRName" -ErrorAction silentlycontinue
			
			if(!$Ldr){
			
				# DLR Appliance has the uplink router interface created first.
				My-Logger "Creating DLR $DLRName" "Green"
				$LdrvNic0 = New-NsxLogicalRouterInterfaceSpec -type Uplink -Name $TransitLsName -ConnectedTo $TransitLs -PrimaryAddress $DLRUplinkAddress -SubnetPrefixLength $DefaultSubnetBits
			
				# HA will be enabled			
					
				My-Logger "Enabling HA for $DLRName" "Green"
				# The DLR is created with the first vnic defined, and the datastore and cluster on which the Control VM will be deployed.

				$Ldr = New-NsxLogicalRouter -name $DLRName -interface $LdrvNic0 -ManagementPortGroup $MgmtLs  -Cluster $cluster -datastore $DataStore -EnableHA
				
				# Create DLR Internal Interfaces
				My-Logger "Adding VNF LIFs to DLR" "Green"
				
				$Ldr = Get-NsxLogicalRouter  -name $DLRName
				foreach ($item in  $VNFExternalNetworks)  {
				
					$LSName =$item[0]
					$DLRLIFIP = $item[1]
					$VNFLs = Get-NsxLogicalSwitch $LSName
					$ldr | New-NsxLogicalRouterInterface -Name $LSName -Type internal -ConnectedTo $VNFLs -PrimaryAddress $DLRLIFIP -SubnetPrefixLength $DefaultSubnetBits | out-null
				}
				
				# Set DLR Password via XML Element
				$Ldr = Get-NsxLogicalRouter  -name $DLRName

				Add-XmlElement -xmlRoot $Ldr.CliSettings -xmlElementName "password" -xmlElementText $AppliancePassword 
				$ldr | Set-NsxLogicalRouter -confirm:$false | out-null
				
				# Change DLR Name
				My-Logger "DLR Hostname is setting ..." "Green"
				$Ldr = Get-NsxLogicalRouter  -name $DLRName
				$Ldr.fqdn="$DLRName"
				$ldr | Set-NsxLogicalRouter -confirm:$false | out-null

					## Enable DLR Syslog
				
					if ($sysLogServer) {
					
						My-Logger "Setting Syslog server for $DLRName" "Green"
						$Ldr = get-nsxlogicalrouter $DLRName
						$LdrID = $Ldr.id
							
						$apistr="/api/4.0/edges/$LdrID/syslog/config"
						$body="<syslog>
						<enabled>true</enabled>
						<protocol>udp</protocol>
						<serverAddresses>
						<ipAddress>$sysLogServer</ipAddress>
						</serverAddresses>
						</syslog>"

						Invoke-NsxRestMethod  -Method put -Uri $apistr -body $body | out-null
					}
					
				## Disable DLR firewall
				My-Logger "Disabling DLR Firewall..." "Green"
				$Ldr = get-nsxlogicalrouter $DLRName
				$Ldr.features.firewall.enabled = "false"
				$Ldr | Set-nsxlogicalrouter -confirm:$false | out-null

			}
		}
		
		######################################
		# EDGE

		$Edge1 = Get-NsxEdge -name $PLR01Name
			
			if(!$Edge1) {
			
				## Defining the uplink and internal interfaces to be used when deploying the edge. Note there are two IP addresses on these interfaces. $EdgeInternalSecondaryAddress and $EdgeUplinkSecondaryAddress are the VIPs
				$EdgeUplinkNetwork = get-vdportgroup $EdgeUplinkNetworkName -errorAction Stop
				$edgevnic0 = New-NsxEdgeinterfacespec -index 0 -Name "Uplink" -type Uplink -ConnectedTo $EdgeUplinkNetwork -PrimaryAddress $PLR01UplinkAddress -SubnetPrefixLength $DefaultSubnetBits
				$edgevnic1 = New-NsxEdgeinterfacespec -index 1 -Name $TransitLsName -type Internal -ConnectedTo $TransitLs -PrimaryAddress $PLR01InternalAddress -SubnetPrefixLength $DefaultSubnetBits

				## Deploy appliance with the defined uplinks
				My-Logger "Creating Edge $PLR01Name" "Green"

				# If Prod deployment disable esg firewall
				
					if($global.PLRMode -eq "HA"){
						$Edge1 = New-NsxEdge -name $PLR01Name -hostname $PLR01Name -cluster $Cluster -datastore $DataStore -Interface $edgevnic0, $edgevnic1 -Password $AppliancePassword -FwEnabled:$false  -enablessh -enableHA 
					}
					else{
						$Edge1 = New-NsxEdge -name $PLR01Name -hostname $PLR01Name -cluster $Cluster -datastore $DataStore -Interface $edgevnic0, $edgevnic1 -Password $AppliancePassword -FwEnabled:$false -enablessh
					}
							
				# Disabling Reverse Path Forwarding (RPF) for $PLR02Name  ...
				$Edge1 = Get-NsxEdge -name $PLR01Name			
				$Edge1Id=$Edge1.id
				
				$apistr="/api/4.0/edges/$Edge1Id/systemcontrol/config"
				$body="<systemControl>
				<property>sysctl.net.ipv4.conf.all.rp_filter=0</property>
				<property>sysctl.net.ipv4.conf.vNic_0.rp_filter=0</property>
				<property>sysctl.net.ipv4.conf.vNic_1.rp_filter=0</property>
				</systemControl>"

				Invoke-NsxRestMethod  -Method put -Uri $apistr -body $body | out-null
				
				## Enable Syslog
					if ($sysLogServer ) {
				
						My-Logger "Setting syslog server for $PLR01Name" "Green"
						
						$Edge1 = get-NSXEdge -name $PLR01Name
						$Edge1Id=$Edge1.id
							
						$apistr="/api/4.0/edges/$Edge1Id/syslog/config"
						$body="<syslog>
						<enabled>true</enabled>
						<protocol>udp</protocol>
						<serverAddresses>
						<ipAddress>$sysLogServer</ipAddress>
						</serverAddresses>
						</syslog>"

						Invoke-NsxRestMethod  -Method put -Uri $apistr -body $body | out-null
					}
					
			 }
		 
					 
				$Edge2 = Get-NsxEdge -name $PLR02Name
			
				if(!$Edge2) {
				
					## Defining the uplink and internal interfaces to be used when deploying the edge. Note there are two IP addreses on these interfaces. $EdgeInternalSecondaryAddress and $EdgeUplinkSecondaryAddress are the VIPs
					$EdgeUplinkNetwork = get-vdportgroup $EdgeUplinkNetworkName -errorAction Stop
					$edgevnic0 = New-NsxEdgeinterfacespec -index 0 -Name "Uplink" -type Uplink -ConnectedTo $EdgeUplinkNetwork -PrimaryAddress $PLR02UplinkAddress -SubnetPrefixLength $DefaultSubnetBits
					$edgevnic1 = New-NsxEdgeinterfacespec -index 1 -Name $TransitLsName -type Internal -ConnectedTo $TransitLs -PrimaryAddress $PLR02InternalAddress -SubnetPrefixLength $DefaultSubnetBits
			
					## Deploy appliance with the defined uplinks
					My-Logger "Creating Edge $PLR02Name" "Green" 
					$Edge2 = New-NsxEdge -name $PLR02Name -hostname $PLR02Name -cluster $Cluster -datastore $DataStore -Interface $edgevnic0, $edgevnic1 -Password $AppliancePassword -FwEnabled:$false -enablessh
					
					# Disabling Reverse Path Forwarding (RPF) for $PLR02Name  ...
					$Edge2 = Get-NsxEdge -name $PLR02Name			
					$Edge2Id=$Edge2.id
					
					$apistr="/api/4.0/edges/$Edge2Id/systemcontrol/config"
					$body="<systemControl>
					<property>sysctl.net.ipv4.conf.all.rp_filter=0</property>
					<property>sysctl.net.ipv4.conf.vNic_0.rp_filter=0</property>
					<property>sysctl.net.ipv4.conf.vNic_1.rp_filter=0</property>
					</systemControl>"

					Invoke-NsxRestMethod  -Method put -Uri $apistr -body $body | out-null
					
					## Enable Syslog
						if ($sysLogServer ) {
				
							My-Logger "Setting syslog server for $PLR02Name" "Green"
							$Edge2 = Get-NSXEdge -name $PLR02Name
							$Edge2Id=$Edge2.id
								
							$apistr="/api/4.0/edges/$Edge2Id/syslog/config"
							$body="<syslog>
							 <enabled>true</enabled>
							<protocol>udp</protocol>
							<serverAddresses>
							<ipAddress>$sysLogServer</ipAddress>
							</serverAddresses>
							</syslog>"

							Invoke-NsxRestMethod  -Method put -Uri $apistr -body $body | out-null
						}
						
				My-Logger "Creating Anti Affinity Rules for PLRs" "Green"
				$antiAffinityVMs=Get-VM | Where {$_.name -like "$PLR01Name*" -or $_.name -like "$PLR02Name*"}
				New-DrsRule -Cluster $VMCluster -Name SeperatePLRs -KeepTogether $false -VM $antiAffinityVMs | out-null
			 }
			
		
		#####################################
		# BGP #

		if($RoutingProtocol -eq "BGP"){    
		
			#$s = $VNFPrimaryAddress.split(".")
			#$DLRVNFStaticRoute = $s[0]+"."+$s[1]+"."+$s[2]+".0/"+$DefaultSubnetBits
		
			My-Logger "Configuring BGP on $PLR01Name" "green"		
			$rtg = Get-NsxEdge $PLR01Name | Get-NsxEdgeRouting
			$rtg | Set-NsxEdgeRouting -EnableEcmp -EnableBgp -RouterId $PLR01UplinkAddress -LocalAS $iBGPAS -Confirm:$false | out-null

			$rtg = Get-NsxEdge $PLR01Name | Get-NsxEdgeRouting			
			$rtg | New-NsxEdgeBgpNeighbour -IpAddress $DLR01ProtocolAddress -RemoteAS $iBGPAS -KeepAliveTimer $BGPKeepAliveTimer -HoldDownTimer $BGPHoldDownTimer  -confirm:$false | out-null
			$rtg = Get-NsxEdge $PLR01Name | Get-NsxEdgeRouting	
			$rtg | New-NsxEdgeBgpNeighbour -IpAddress $PLReBGPNeigbour1 -RemoteAS $eBGPAS -KeepAliveTimer $BGPKeepAliveTimer -HoldDownTimer $BGPHoldDownTimer  -confirm:$false | out-null
			
			$rtg = Get-NsxEdge $PLR01Name | Get-NsxEdgeRouting		
			$rtg | Set-NsxEdgeBgp -GracefulRestart:$false -Confirm:$false | out-null
			
			#write-host -foregroundcolor Green "Configuring Floating Static Routes $PLR01Name"
			
			#Get-NsxEdge $PLR01Name | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network $DLRVNFStaticRoute -NextHop $DLR01ProtocolAddress -AdminDistance 240 -confirm:$false | out-null

				if($PLRMode -eq "ECMP"){
	 
					My-Logger "Configuring $PLR02Name BGP" "green"
					$rtg = Get-NsxEdge $PLR02Name | Get-NsxEdgeRouting
					$rtg | Set-NsxEdgeRouting -EnableEcmp -EnableBgp -RouterId $PLR02UplinkAddress -LocalAS $iBGPAS -Confirm:$false | out-null
					
					$rtg = Get-NsxEdge $PLR02Name | Get-NsxEdgeRouting
					$rtg | New-NsxEdgeBgpNeighbour -IpAddress $DLR01ProtocolAddress -RemoteAS $iBGPAS -KeepAliveTimer $BGPKeepAliveTimer -HoldDownTimer $BGPHoldDownTimer  -confirm:$false | out-null
					$rtg = Get-NsxEdge $PLR02Name | Get-NsxEdgeRouting
					$rtg | New-NsxEdgeBgpNeighbour -IpAddress $PLReBGPNeigbour1 -RemoteAS $eBGPAS -KeepAliveTimer $BGPKeepAliveTimer -HoldDownTimer $BGPHoldDownTimer  -confirm:$false | out-null
								
					$rtg = Get-NsxEdge $PLR02Name | Get-NsxEdgeRouting
					$rtg | Set-NsxEdgeBgp -GracefulRestart:$false -Confirm:$false | out-null
					
					#write-host -foregroundcolor Green "Configuring Floating Static Routes for $PLR02Name "
					#Get-NsxEdge $PLR02Name | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network $DLRVNFStaticRoute -NextHop $DLR01ProtocolAddress -AdminDistance 250 -confirm:$false | out-null
					
				}
			
			My-Logger "Configuring BGP on DLR" "green"
			
				if($PLRMode -eq "ECMP"){
				
					Get-NsxLogicalRouter $DLRName | Get-NsxLogicalRouterRouting | set-NsxLogicalRouterRouting -EnableEcmp -EnableBgp -RouterId $DLRUplinkAddress -LocalAS $iBGPAS -ProtocolAddress $DLR01ProtocolAddress -ForwardingAddress $DLRUplinkAddress -confirm:$false | out-null
					Get-NsxLogicalRouter $DLRName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterBgpNeighbour -IpAddress $PLR02InternalAddress -RemoteAS $iBGPAS -ProtocolAddress $DLR01ProtocolAddress -ForwardingAddress $DLRUplinkAddress  -KeepAliveTimer $BGPKeepAliveTimer -HoldDownTimer $BGPHoldDownTimer -confirm:$false | out-null
					Get-NsxLogicalRouter $DLRName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterBgpNeighbour -IpAddress $PLR01InternalAddress -RemoteAS $iBGPAS -ProtocolAddress $DLR01ProtocolAddress -ForwardingAddress $DLRUplinkAddress  -KeepAliveTimer $BGPKeepAliveTimer -HoldDownTimer $BGPHoldDownTimer -confirm:$false | out-null
				}
				else {
					Get-NsxLogicalRouter $DLRName | Get-NsxLogicalRouterRouting | set-NsxLogicalRouterRouting -EnableEcmp:$false -EnableBgp -RouterId $DLRUplinkAddress -LocalAS $iBGPAS -ProtocolAddress $DLR01ProtocolAddress -ForwardingAddress $DLRUplinkAddress -confirm:$false | out-null
					Get-NsxLogicalRouter $DLRName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterBgpNeighbour -IpAddress $PLR02InternalAddress -RemoteAS $iBGPAS -ProtocolAddress $DLR01ProtocolAddress -ForwardingAddress $DLRUplinkAddress  -KeepAliveTimer $BGPKeepAliveTimer -HoldDownTimer $BGPHoldDownTimer -confirm:$false | out-null
				}
			
				
			My-Logger "Configuring Route Redistribution" "green"
			Get-NsxLogicalRouter $DLRName | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableOspfRouteRedistribution:$false -confirm:$false | out-null
			Get-NsxLogicalRouter $DLRName | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableBgpRouteRedistribution:$true -confirm:$false | out-null
			Get-NsxLogicalRouter $DLRName | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule -Learner ospf | Remove-NsxLogicalRouterRedistributionRule -Confirm:$false | out-null
			Get-NsxLogicalRouter $DLRName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterRedistributionRule -Learner bgp -FromConnected -Action permit -confirm:$false | out-null
			
			Get-NsxEdge $PLR01Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableOspfRouteRedistribution:$false -confirm:$false | out-null
			Get-NsxEdge $PLR01Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableBgpRouteRedistribution:$true -confirm:$false | out-null
			Get-NsxEdge $PLR01Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -Learner ospf | Remove-NsxEdgeRedistributionRule -Confirm:$false | out-null
			Get-NsxEdge $PLR01Name | Get-NsxEdgeRouting | New-NsxEdgeRedistributionRule -Learner bgp -FromConnected -FromStatic -Action permit -confirm:$false | out-null
			
				if($PLRMode -eq "ECMP"){
					Get-NsxEdge $PLR02Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableOspfRouteRedistribution:$false -confirm:$false | out-null
					Get-NsxEdge $PLR02Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableBgpRouteRedistribution:$true -confirm:$false | out-null
					Get-NsxEdge $PLR02Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -Learner ospf | Remove-NsxEdgeRedistributionRule -Confirm:$false | out-null
					Get-NsxEdge $PLR02Name | Get-NsxEdgeRouting | New-NsxEdgeRedistributionRule -Learner bgp -FromConnected -FromStatic -Action permit -confirm:$false | out-null
				}
			My-Logger "Disabling Graceful Restart" "green"
			$rtg = Get-NsxLogicalRouter $DLRName | Get-NsxLogicalRouterRouting
			$rtg | Set-NsxLogicalRouterBgp -GracefulRestart:$false -confirm:$false | out-null
	  
		}
		
		My-Logger "NSX $DeploymentIPModel VNF Configuration Complete" "white"
		$EndTime = Get-Date
		$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)
		write-host "Duration: $duration minutes"
	}
	
	if($DeploymentIPModel -eq "IPv6"){	
		# Creates logical switches 
		
		 My-Logger "Creating Logical Switches..." "Green"  
	 
			if (Get-NsxLogicalSwitch $VNFNetworkLsNameIPv6 ) {
				$VNFNetworkLsIPv6 = Get-NsxLogicalSwitch $VNFNetworkLsNameIPv6    
				My-Logger "$VNFNetworkLsNameIPv6  is already exist..." "Yellow" 			
			}
			else {
				$VNFNetworkLsIPv6 = Get-NsxTransportZone -name $TransportZoneName | New-NsxLogicalSwitch $VNFNetworkLsNameIPv6 |out-null
			}
			if (Get-NsxLogicalSwitch $EdgeHALsNameIPv6) {
			
				$MgmtLs = Get-NsxLogicalSwitch $EdgeHALsNameIPv6   
				My-Logger "$EdgeHALsNameIPv6 is already exist..." "Yellow" 			
			}
			else {
				$MgmtLs = Get-NsxTransportZone -name $TransportZoneName | New-NsxLogicalSwitch $EdgeHALsNameIPv6 |out-null
			}
		
		$Edge = Get-NsxEdge -name $PLRNameIPv6
			
			if(!$Edge) {
			
				## Defining the uplink and internal interfaces to be used when deploying the edge. Note there are two IP addresses on these interfaces. $EdgeInternalSecondaryAddress and $EdgeUplinkSecondaryAddress are the VIPs
				$EdgeUplinkNetwork = get-vdportgroup $EdgeUplinkNetworkNameIPv6 -errorAction Stop
				$edgevnic0 = New-NsxEdgeinterfacespec -index 0 -Name "Uplink" -type Uplink -ConnectedTo $EdgeUplinkNetwork -PrimaryAddress $PLRUplinkAddressIPv6 -SubnetPrefixLength $IPv6Prefix
				$edgevnic1 = New-NsxEdgeinterfacespec -index 1 -Name $VNFNetworkLsNameIPv6 -type Internal -ConnectedTo $VNFNetworkLsIPv6 -PrimaryAddress $PLRInternalAddressIPv6 -SubnetPrefixLength $IPv6Prefix

				## Deploy appliance with the defined uplinks
				My-Logger "Creating Edge $PLRNameIPv6" "Green" 

				# Enable HA
									
			    $Edge = New-NsxEdge -name $PLRNameIPv6 -hostname $PLRNameIPv6 -cluster $Cluster -datastore $DataStore -Interface $edgevnic0, $edgevnic1 -Password $AppliancePassword -FwEnabled:$false  -enablessh -enableHA 
			
				##Configure Default Gateway
			
				Get-NSXEdge -name $PLRNameIPv6 | Get-NsxEdgeRouting | Set-NsxEdgeRouting -DefaultGatewayAddress $PLRDefaultGWIPv6 -confirm:$false | out-null
						
				## Enable Syslog
					if ($sysLogServer ) {
				
						My-Logger "Setting syslog server for $PLR01Name" "Green" 
						
						$Edge1 = get-NSXEdge -name $PLR01Name
						$Edge1Id=$Edge1.id
							
						$apistr="/api/4.0/edges/$Edge1Id/syslog/config"
						$body="<syslog>
						<enabled>true</enabled>
						<protocol>udp</protocol>
						<serverAddresses>
						<ipAddress>$sysLogServer</ipAddress>
						</serverAddresses>
						</syslog>"

						Invoke-NsxRestMethod  -Method put -Uri $apistr -body $body | out-null
					}
					
			 }
		
		My-Logger "NSX $DeploymentIPModel Configuration Complete" "White"  
		$EndTime = Get-Date
		$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)
		write-host "Duration: $duration minutes"
	}
Disconnect-VIServer $viConnection -Confirm:$false
Disconnect-NsxServer
