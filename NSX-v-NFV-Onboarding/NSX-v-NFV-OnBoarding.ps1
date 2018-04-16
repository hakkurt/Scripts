<# 
    NSX Deployment for NFV Onboarding
	Created by Hakan Akkurt
	https://www.linkedin.com/in/hakkurt/
	April 2018
    	
	Script Functionalities
	
	- Create VNF Logical Switches
	- Create DLR or UDLR based on selected option
	- Create DLR LIF for VNF
	- Create ESGs (HA or ECMP mode)
	- Create Anti-affinity rules for ESGs (for ECMP mode)
	- Configure routing based on ESG model(static or BGP)
	- Configure route redistribution
	- Configure floating static routes on ESGs
	- Enable ECMP, Disable Graceful Restart and RFP
	- Set Syslog for all components
	
#>

$ScriptVersion = "1.0"
$VNFPrefix = "VoLTE"
$VNFDesc = "Nokia VoLTE"

# Deployment Parameters
$verboseLogFile = "ScriptLogs.log"

# vCenter Configuration
$VIServer = "dt-odc4-vcsa01.onat.local"
$PSCServer = "dt-odc4-psc01.onat.local"
$VIUsername = "administrator@vsphere.local"
$VIPassword = "VMware1!"

# NSX Configuration
$NSXHostname = "dt-odc4-nsx01.onat.local"
$NSXUIPassword = "VMware1!"
$VMDatastore = "ODC4-LDS2-esxi01"
$VMCluster = "CL-ODC4-COMP01"
$EdgeUplinkNetworkName1 = "UL1"
$EdgeUplinkNetworkName2 = "UL2"
$TransportZoneName = "TZ4"

# Logical Switches / Router Names 
$TransitLsName = $VNFPrefix+"-LS-Transit" 
$VNFLsName =  $VNFPrefix+"-LS-01" 
$EdgeHALsName = $VNFPrefix+"-LS-HA"
$PLR01Name = $VNFPrefix+"-Edge01"
$PLR02Name = $VNFPrefix+"-Edge02" 
$DLRName = $VNFPrefix+"-DLR01"
$UDLRName = $VNFPrefix+"-UDLR01"

#Get-Random -Maximum 100 - Can be used for Object name creation

# Routing Topology 
$DeploymentIPModel = "IPv4" # Select IPv4 or IPv6
$DeploymentNSXModel = "Local" # Select Local or Universal
$PLR01InternalAddress = "10.0.4.11" 
$PLR01UplinkAddress = "192.168.4.11" 
$PLR01Size = "Large"
$PLR02InternalAddress = "10.0.4.12" 
$PLR02UplinkAddress = "192.168.4.12" 
$PLR02DefaultGW = "192.168.4.1"
$PLR02Size = "Large"
$PLRDefaultGW = ":200::/64"
$PLReBGPNeigbour1 ="192.168.5.1"
$DLRUplinkAddress = "10.0.5.1"
$DLR01ProtocolAddress = "10.0.5.2" 
$VNFPrimaryAddress = "10.0.25.1" 
$DefaultSubnetMask = "255.255.255.0" 
$DefaultSubnetBits = "24" 
$AppliancePassword = "VMware1!VMware1!"
$RoutingProtocol = "BGP" # Select BGP or Static
$PLRMode = "ECMP" # Select ECMP or HA
$iBGPAS = "65531" 
$eBGPAS = "65532"
$BGPKeepAliveTimer = "1"
$BGPHoldDownTimer = "3"

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
    [String]$message
    )

    $timeStamp = Get-Date -Format "MM-dd-yyyy_hh:mm:ss"

    Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
    Write-Host -ForegroundColor Green " $message"
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

	Write-Host -ForegroundColor Yellow "Checking PowerCli and PowerNSX Modules ..."
	
	$PSVersion=$PSVersionTable.PSVersion.Major
	
	# If you manually install PowerCLI and PowerNSX, you can remove this part
	if($PSVersion -le 4) {
		Write-Host -ForegroundColor red "You're using older version of Powershell. Please upgrade your Powershell from following URL :"
		Write-Host -ForegroundColor red "https://www.microsoft.com/en-us/download/details.aspx?id=54616"
		exit
	}
	
	Find-Module VMware.PowerCLI | Install-Module –Scope CurrentUser -Confirm:$False
	Find-Module PowerNSX | Install-Module -Scope CurrentUser -Confirm:$False

	Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -confirm:$false | out-null
	Set-PowerCLIConfiguration -invalidcertificateaction Ignore -confirm:$false | out-null
	Set-PowerCLIConfiguration -Scope Session -WebOperationTimeoutSeconds 3600 -confirm:$false | out-null
	
	Write-Host -ForegroundColor green "PowerCli and PowerNSX Modules check completed..."
	
	$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue
		
	 try {
	 
	 Write-Host "   -> Connecting NSX Manager..."
	 
		if(!(Connect-NSXServer -Server $NSXHostname -Username admin -Password $NSXUIPassword -DisableVIAutoConnect -WarningAction SilentlyContinue)) {
			Write-Host -ForegroundColor Red "Unable to connect to NSX Manager, please check the deployment"
			exit
		} else {
			Write-Host "Successfully logged into NSX Manager $global:NSXHostname..."
		}
	
	}
	
	catch {
		Throw  "Error while connecting NSX Manager"
	}  
	
	$cluster = Get-Cluster -Name $VMCluster -errorAction Stop		
	$datastore = Get-Datastore -Name $VMDatastore -errorAction Stop
	#$PortGroup = Get-VdPortGroup $ControllerNetworkPortGroupName -errorAction Stop
	 
	 ###################################### 
     #Logical Switches 
 
	# Creates four logical switches 
	
     write-host -foregroundcolor "Green" "Creating Logical Switches..." 
 
        if (Get-NsxLogicalSwitch $VNFLsName) {
			$VNFLs = Get-NsxLogicalSwitch $VNFLsName   
			write-host -foregroundcolor "Yellow" "	$VNFLsName is already exist..."			
        }
		else {
			$VNFLs = Get-NsxTransportZone -name $TransportZoneName | New-NsxLogicalSwitch $VNFLsName
		}

		if (Get-NsxLogicalSwitch $TransitLsName) {
			$TransitLs = Get-NsxLogicalSwitch $TransitLsName   
			write-host -foregroundcolor "Yellow" "	$TransitLsName is already exist..."			
        }
		else {
			$TransitLs = Get-NsxTransportZone -name $TransportZoneName | New-NsxLogicalSwitch $TransitLsName
		}
		if (Get-NsxLogicalSwitch $EdgeHALsName) {
		
			$MgmtLs = Get-NsxLogicalSwitch $EdgeHALsName   
			write-host -foregroundcolor "Yellow" "	$EdgeHALsName is already exist..."				
        }
		else {
			$MgmtLs = Get-NsxTransportZone -name $TransportZoneName | New-NsxLogicalSwitch $EdgeHALsName 
		}

	######################################
    # DLR
	
	if($DeploymentNSXModel -eq "Local"){
	
		$Ldr = Get-NsxLogicalRouter -Name "$DLRName" -ErrorAction silentlycontinue
		
		if(!$Ldr){
		
			# DLR Appliance has the uplink router interface created first.
			write-host -foregroundcolor "Green" "Creating DLR"
			$LdrvNic0 = New-NsxLogicalRouterInterfaceSpec -type Uplink -Name $TransitLsName -ConnectedTo $TransitLs -PrimaryAddress $DLRUplinkAddress -SubnetPrefixLength $DefaultSubnetBits

			# HA will be enabled			
				
			write-host -foregroundcolor "Green" "Enabling HA for $DLRName"
			# The DLR is created with the first vnic defined, and the datastore and cluster on which the Control VM will be deployed.

			$Ldr = New-NsxLogicalRouter -name $DLRName -interface $LdrvNic0 -ManagementPortGroup $MgmtLs  -Cluster $cluster -datastore $DataStore -EnableHA
					
			# Set DLR Password via XML Element
			$Ldr = Get-NsxLogicalRouter  -name $DLRName

			Add-XmlElement -xmlRoot $Ldr.CliSettings -xmlElementName "password" -xmlElementText $AppliancePassword 
			$ldr | Set-NsxLogicalRouter -confirm:$false | out-null
			
			# Change DLR Name
			write-host -foregroundcolor Green "DLR Hostname is setting ..."
			$Ldr = Get-NsxLogicalRouter  -name $DLRName
			$Ldr.fqdn="$DLRName"
			$ldr | Set-NsxLogicalRouter -confirm:$false | out-null

							
			## Adding DLR interfaces after the DLR has been deployed. This can be done any time if new interfaces are required.
			write-host -foregroundcolor Green "Adding VNF LIF to DLR"
			$Ldr | New-NsxLogicalRouterInterface -Type Internal -name $VNFLsName  -ConnectedTo $VNFLs -PrimaryAddress $VNFPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits | out-null

			
				## Enable DLR Syslog
			
				if ($sysLogServer) {
				
				write-host -foregroundcolor Green "Setting Syslog server for $DLRName"
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
			$EdgeUplinkNetwork = get-vdportgroup $EdgeUplinkNetworkName1 -errorAction Stop
			$edgevnic0 = New-NsxEdgeinterfacespec -index 0 -Name "Uplink" -type Uplink -ConnectedTo $EdgeUplinkNetwork -PrimaryAddress $PLR01UplinkAddress -SubnetPrefixLength $DefaultSubnetBits
			$edgevnic1 = New-NsxEdgeinterfacespec -index 1 -Name $TransitLsName -type Internal -ConnectedTo $TransitLs -PrimaryAddress $PLR01InternalAddress -SubnetPrefixLength $DefaultSubnetBits
			## Deploy appliance with the defined uplinks
			write-host -foregroundcolor "Green" "Creating Edge $PLR01Name"
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
			
					write-host -foregroundcolor Green "Setting syslog server for $PLR01Name"
					
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
					
				if($RoutingProtocol -eq "Static"){
					##Configure Edge DGW
					Get-NSXEdge $PLR01Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -DefaultGatewayAddress $PLRDefaultGW -confirm:$false | out-null
				}
				
		 }
	 
	 	 if($PLRMode -eq "ECMP"){
		 
			$Edge2 = Get-NsxEdge -name $PLR02Name
		
			if(!$Edge2) {
			
				## Defining the uplink and internal interfaces to be used when deploying the edge. Note there are two IP addreses on these interfaces. $EdgeInternalSecondaryAddress and $EdgeUplinkSecondaryAddress are the VIPs
				$EdgeUplinkNetwork = get-vdportgroup $EdgeUplinkNetworkName1 -errorAction Stop
				$edgevnic0 = New-NsxEdgeinterfacespec -index 0 -Name "Uplink" -type Uplink -ConnectedTo $EdgeUplinkNetwork -PrimaryAddress $PLR02UplinkAddress -SubnetPrefixLength $DefaultSubnetBits
				$edgevnic1 = New-NsxEdgeinterfacespec -index 1 -Name $TransitLsName -type Internal -ConnectedTo $TransitLs -PrimaryAddress $PLR02InternalAddress -SubnetPrefixLength $DefaultSubnetBits
				## Deploy appliance with the defined uplinks
				write-host -foregroundcolor "Green" "Creating Edge $PLR02Name"
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
			
						write-host -foregroundcolor Green "Setting syslog server for $PLR02Name"
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
					
										
			 }
						 
			write-host "   -> Creating Anti Affinity Rules for PLRs"
			$antiAffinityVMs=Get-VM | Where {$_.name -like "$PLR01Name*" -or $_.name -like "$PLR02Name*"}
			New-DrsRule -Cluster $VMCluster -Name SeperatePLRs -KeepTogether $false -VM $antiAffinityVMs | out-null
		 }
		
	
	#####################################
    # BGP #

	if($RoutingProtocol -eq "BGP"){    
	
			
		$s = $VNFPrimaryAddress.split(".")
		$DLRVNFStaticRoute = $s[0]+"."+$s[1]+"."+$s[2]+".0/"+$DefaultSubnetBits
	
		write-host -foregroundcolor Green "Configuring $PLR01Name BGP"		
		$rtg = Get-NsxEdge $PLR01Name | Get-NsxEdgeRouting
		$rtg | Set-NsxEdgeRouting -EnableEcmp -EnableBgp -RouterId $PLR01InternalAddress -LocalAS $iBGPAS -Confirm:$false | out-null

		$rtg = Get-NsxEdge $PLR01Name | Get-NsxEdgeRouting			
		$rtg | New-NsxEdgeBgpNeighbour -IpAddress $DLR01ProtocolAddress -RemoteAS $iBGPAS -KeepAliveTimer $BGPKeepAliveTimer -HoldDownTimer $BGPHoldDownTimer  -confirm:$false | out-null
		$rtg = Get-NsxEdge $PLR01Name | Get-NsxEdgeRouting	
		$rtg | New-NsxEdgeBgpNeighbour -IpAddress $PLReBGPNeigbour1 -RemoteAS $eBGPAS -KeepAliveTimer $BGPKeepAliveTimer -HoldDownTimer $BGPHoldDownTimer  -confirm:$false | out-null
		
		$rtg = Get-NsxEdge $PLR01Name | Get-NsxEdgeRouting		
		$rtg | Set-NsxEdgeBgp -GracefulRestart:$false -Confirm:$false | out-null
		
		
		write-host -foregroundcolor Green "Configuring Floating Static Routes $PLR01Name"
		
		Get-NsxEdge $PLR01Name | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network $DLRVNFStaticRoute -NextHop $DLR01ProtocolAddress -AdminDistance 240 -confirm:$false | out-null

		
			if($PLRMode -eq "ECMP"){
 
				write-host -foregroundcolor Green "Configuring $PLR02Name BGP"
				$rtg = Get-NsxEdge $PLR02Name | Get-NsxEdgeRouting
				$rtg | Set-NsxEdgeRouting -EnableEcmp -EnableBgp -RouterId $PLR02InternalAddress -LocalAS $iBGPAS -Confirm:$false | out-null
				
				$rtg = Get-NsxEdge $PLR02Name | Get-NsxEdgeRouting
				$rtg | New-NsxEdgeBgpNeighbour -IpAddress $DLR01ProtocolAddress -RemoteAS $iBGPAS -KeepAliveTimer $BGPKeepAliveTimer -HoldDownTimer $BGPHoldDownTimer  -confirm:$false | out-null
				$rtg = Get-NsxEdge $PLR02Name | Get-NsxEdgeRouting
				$rtg | New-NsxEdgeBgpNeighbour -IpAddress $PLReBGPNeigbour1 -RemoteAS $eBGPAS -KeepAliveTimer $BGPKeepAliveTimer -HoldDownTimer $BGPHoldDownTimer  -confirm:$false | out-null
							
				$rtg = Get-NsxEdge $PLR02Name | Get-NsxEdgeRouting
				$rtg | Set-NsxEdgeBgp -GracefulRestart:$false -Confirm:$false | out-null
				
				write-host -foregroundcolor Green "Configuring Floating Static Routes for $PLR02Name "
				Get-NsxEdge $PLR02Name | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network $DLRVNFStaticRoute -NextHop $DLR01ProtocolAddress -AdminDistance 250 -confirm:$false | out-null
				
			}
		
		write-host -foregroundcolor Green "Configuring DLR BGP"
		
			if($PLRMode -eq "ECMP"){
			
				Get-NsxLogicalRouter $DLRName | Get-NsxLogicalRouterRouting | set-NsxLogicalRouterRouting -EnableEcmp -EnableBgp -RouterId $DLRUplinkAddress -LocalAS $iBGPAS -ProtocolAddress $DLR01ProtocolAddress -ForwardingAddress $DLRUplinkAddress -confirm:$false | out-null
				Get-NsxLogicalRouter $DLRName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterBgpNeighbour -IpAddress $PLR02InternalAddress -RemoteAS $iBGPAS -ProtocolAddress $DLR01ProtocolAddress -ForwardingAddress $DLRUplinkAddress  -KeepAliveTimer $BGPKeepAliveTimer -HoldDownTimer $BGPHoldDownTimer -confirm:$false | out-null
				Get-NsxLogicalRouter $DLRName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterBgpNeighbour -IpAddress $PLR01InternalAddress -RemoteAS $iBGPAS -ProtocolAddress $DLR01ProtocolAddress -ForwardingAddress $DLRUplinkAddress  -KeepAliveTimer $BGPKeepAliveTimer -HoldDownTimer $BGPHoldDownTimer -confirm:$false | out-null
			}
			else {
				Get-NsxLogicalRouter $DLRName | Get-NsxLogicalRouterRouting | set-NsxLogicalRouterRouting -EnableEcmp:$false -EnableBgp -RouterId $DLRUplinkAddress -LocalAS $iBGPAS -ProtocolAddress $DLR01ProtocolAddress -ForwardingAddress $DLRUplinkAddress -confirm:$false | out-null
				Get-NsxLogicalRouter $DLRName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterBgpNeighbour -IpAddress $PLR02InternalAddress -RemoteAS $iBGPAS -ProtocolAddress $DLR01ProtocolAddress -ForwardingAddress $DLRUplinkAddress  -KeepAliveTimer $BGPKeepAliveTimer -HoldDownTimer $BGPHoldDownTimer -confirm:$false | out-null
			}
		
	         
		write-host -foregroundcolor Green "Configuring Route Redistribution"
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
		write-host -foregroundcolor Green "Disabling Graceful Restart"
		$rtg = Get-NsxLogicalRouter $DLRName | Get-NsxLogicalRouterRouting
        $rtg | Set-NsxLogicalRouterBgp -GracefulRestart:$false -confirm:$false | out-null
  
	}
	
     write-host -foregroundcolor green "`nNSX VNF Configuration Complete`n" 
 		
	Disconnect-NsxServer