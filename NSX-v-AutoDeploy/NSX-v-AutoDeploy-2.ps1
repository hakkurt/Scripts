<# 
    Full Blown NSX Deployment with Test or Prod Environments
	Created by Hakan Akkurt
    November 2017
    version 1.3
#>

$ScriptVersion = "1.3"
$global:DeploymentType = "Prod" # Select Prod or Test

# Deployment Parameters
$VIServer = "vcenter.poc.local"
$PSCServer = "vcenter.poc.local"
$VIUsername = "administrator@vsphere.local"
$VIPassword = "VMware1!"
$verboseLogFile = "ScriptLogs.log"
$global:DnsServer1 = "192.168.1.175"
$global:DnsServer2 = "192.168.1.175"
$global:DnsSuffix = "poc.local"
$global:ntp = "192.168.1.175"

# NSX Manager Configuration
$global:NSXOVA =  "C:\Scripts\VMware-NSX-Manager-6.3.5-7119875.ova"
$global:VMNetwork = "Management"
$global:NSXDisplayName = "nsxmgr"
$global:NSXHostname = "nsxmgr.poc.local"
$global:NSXIPAddress = "192.168.1.174"
$global:NSXNetmask = "255.255.255.0"
$global:NSXGateway = "192.168.1.254"
$global:NSXUIPassword = "VMware1!"
$global:NSXCLIPassword = "VMware1!"
$global:VMDatastore = "vsanDatastore"
$global:VMCluster = "Cluster"
$global:NSXssoUsername = "administrator@vsphere.local"
$global:NSXssoPassword = "VMware1!"
$global:NsxlicenseKey = ""
$global:ControllerPoolStartIp = "192.168.1.161"
$global:ControllerPoolEndIp = "192.168.1.163"
$global:ControllerNetworkSubnetMask = "255.255.255.0"
$global:ControllerNetworkSubnetPrefixLength ="24"
$global:ControllerNetworkGateway = "192.168.1.254"
$global:ControllerNetworkPortGroupName = "Management"
$global:EdgeUplinkNetworkName = "Edge Uplink"
$global:ControllerDatastore = "vsanDatastore"
$global:ControllerPassword = "VMware1!VMware1!"
$global:SegmentPoolStart = "5000"
$global:SegmentPoolEnd = "5999"
$global:TransportZoneName = "TZ01"
$global:VxlanMtuSize = 1600 
$global:MgmtVdsName = "vDS"
$global:MgmtVdsVxlanNetworkSubnetMask = "255.255.255.0" 
$global:MgmtVdsVxlanNetworkSubnetPrefixLength = "24" 
$global:MgmtVdsVxlanNetworkGateway = "192.168.4.254" 
$global:MgmtVdsVxlanVlanID = "0" 
$global:MgmtVdsHostVtepCount = 1 
$global:MgmtVdsVtepPoolStartIp = "192.168.4.171" 
$global:MgmtVdsVtepPoolEndIp = "192.168.4.173" 

# Logical Switches / Router Names 
$global:TransitLsName = "LS-Transit" 
$global:WebLsName = "LS-Web" 
$global:AppLsName = "LS-App" 
$global:DbLsName = "LS-DB" 
$global:EdgeHALsName = "LS-HA"
$global:PLR01Name = "Edge1"
$global:PLR02Name = "Edge2" 
$global:DLRName = "DLR1" 

# Routing Topology 
$global:PLR01InternalAddress = "10.0.4.11" 
$global:PLR01UplinkAddress = "192.168.4.11" 
$global:PLR01DefaultGW = "192.168.4.1"
$global:PLR01Size = "Large"
$global:PLR02InternalAddress = "10.0.4.12" 
$global:PLR02UplinkAddress = "192.168.4.12" 
$global:PLR02DefaultGW = "192.168.4.1"
$global:PLR02Size = "Large"
$global:PLReBGPNeigbour1 ="192.168.4.1"
$global:DLRUplinkAddress = "10.0.4.1"
$global:DLR01ProtocolAddress = "10.0.4.2" 
$global:DLRWebPrimaryAddress = "10.0.1.1" 
$global:DLRAppPrimaryAddress = "10.0.2.1" 
$global:DLRDbPrimaryAddress = "10.0.3.1" 
$global:DefaultSubnetMask = "255.255.255.0" 
$global:DefaultSubnetBits = "24" 
$global:AppliancePassword = "VMware1!VMware1!"
$global:RoutingProtocol = "BGP" # Select OSPF, BGP or Static
$global:TransitOspfAreaId = "10"
$global:iBGPAS = "65531" 
$global:eBGPAS = "65532"
$global:BGPKeepAliveTimer = "1"
$global:BGPHoldDownTimer = "3"

$global:NSXvCPU = "2" # Reconfigure NSX vCPU
$global:NSXvMEM = "8" # Reconfigure NSX vMEM (GB)
$global:NumberOfController = "1"

# Parameter initial values

$global:domainname = $null
$global:sysLogServer = "192.168.1.165"
$global:sysLogServerName = $null
$global:sysLogServerPort = "514"
$global:VMHostCount = 0

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

	Write-Host -ForegroundColor Black "Starting NSX Auto Deploy Script version $ScriptVersion"

# Check OVA and PowerNSX
	
	if(!(Test-Path $global:NSXOVA)) {
		Write-Host -ForegroundColor Red "`nUnable to find $NSXOVA ...`nexiting"
		exit
	}

	#Load the VMware PowerCLI tools - no PowerCLI is fatal. 
	
	# Check PowerCli and PowerNSX modules

	Write-Host -ForegroundColor Yellow "Checking PowerCli and PowerNSX Modules ..."
	
	Find-Module VMware.PowerCLI | Install-Module –Scope CurrentUser -Confirm:$False
	Find-Module PowerNSX | Install-Module -Scope CurrentUser -Confirm:$False

	Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -confirm:$false | out-null
	Set-PowerCLIConfiguration -invalidcertificateaction Ignore -confirm:$false | out-null
	Set-PowerCLIConfiguration -Scope Session -WebOperationTimeoutSeconds 3600 -confirm:$false | out-null
	
	Write-Host -ForegroundColor green "PowerCli and PowerNSX Modules check completed..."

	
	<# Do {
	Write-Host "
	--- Select Deployment Type ---
	1 = Production 
	2 = Test
	------------------------------"

	$choice1 = read-host -prompt "Select number & press enter"
	} until ($choice1 -eq "1" -or $choice1 -eq "2")

	Switch ($choice1) {
	"1" {$global:DeploymentType = "Prod"
		 $global:NumberOfController=3
		}
	"2" {$global:DeploymentType = "Test"}
	} #>

$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue

# Deployment Precheck    
Function NSX-Deployment-Precheck {
	
	Write-Host -ForegroundColor green "Pre-check Started..."		
	
	$Cluster = Get-Cluster -Name $global:VMCluster
	
	$ClusterName = $Cluster.name
	
	Write-Host -ForegroundColor yellow "$ClusterName DRS enabled ?" $Cluster.DRSEnabled - $Cluster.DRSAutomationLevel
	$HAAdmissionControlEnabled=$cluster.HAAdmissionControlEnabled
	
			if ($HAAdmissionControlEnabled) {
				Write-Host -ForegroundColor red "HA Admission Control is Enabled. Controller Deployment may fail ..."									
			}
	
	$VMHosts=Get-VMHost -Location $ClusterName
	$ClusterisCompatible = $false
	
		foreach ($VMHost in $VMHosts) {
			
			$VMHostName = $VMHost.name		
			$VMHostMemory=$VMHost.MemoryTotalGB
			$VMHostCPU=$VMHost.NumCpu		
			
			#Write-Host -ForegroundColor White "		Host:" $VMHostName
			
			if (($VMHostMemory -ge 16) -and ($VMHostCPU -ge 4))  {
				$ClusterisCompatible = $true
			}
				
			$global:ntp = Get-VMHostNtpServer -VMHost $VMHost
			if (!$global:ntp ) {
				Write-Host -ForegroundColor red "	No NTP setting on $VMHostName"									
			}
				
			$global:dns =  ($VMHost | Get-VMHostNetwork).DNSAddress
			if (!$global:dns) {
				Write-Host -ForegroundColor red "	No DNS setting on $VMHostName"										
			}
				
			$global:domainname =  ($VMHost | Get-VMHostNetwork).DomainName
			if (!$global:domainname) {
				Write-Host -ForegroundColor red "	No Domain Name setting on $VMHostName"										
			}
				
			$global:sysLogServer =  $VMHost | Get-VMHostSysLogServer				
			if (!$global:sysLogServer ) {
				Write-Host "	No Syslog server setting on $VMHostName"
			}
			else{
				$global:sysLogServerName = $global:sysLogServer.ToString().Split(':')[1] -replace '[//]',''
				$global:sysLogServerPort = $global:sysLogServer.ToString().Split(':')[-1]									
			}	
				#Write-Host -ForegroundColor yellow "			Syslog Server Name :" $sysLogServer							
		}
		
		if (!$ClusterisCompatible) {
				Write-Host -ForegroundColor red "$ClusterName has not sufficient resources for NSX Components Deployment"		
		}
		else {
			Write-Host -ForegroundColor yellow "$ClusterName has sufficient resources for NSX Components Deployment"	
		}
					

	Write-Host -ForegroundColor yellow "Deployment Type :" $global:DeploymentType
	<# Write-Host -ForegroundColor yellow "NTP Servers :" $ntp
	Write-Host -ForegroundColor yellow "DNS Servers :" $dns
	Write-Host -ForegroundColor yellow "Domain Name :" $domainname
	Write-Host -ForegroundColor yellow "Syslog Server :" $sysLogServer #>
	Write-Host -ForegroundColor green "Pre-check Completed"	
}

Function DeployNSXManager {
	# Deploy NSX Manager 

		$NSXManagerVmName = Get-VM -name $global:NSXDisplayName -ErrorAction silentlycontinue
		
		if($NSXManagerVmName){
			Write-Host -ForegroundColor Red "NSX Manager is already deployed"
			return $true
		}
		else
		{
	
		$ovfconfig = Get-OvfConfiguration $global:NSXOVA
        $ovfconfig.NetworkMapping.VSMgmt.value = $global:VMNetwork
        $ovfconfig.common.vsm_hostname.value = $global:NSXHostname
        $ovfconfig.common.vsm_ip_0.value = $global:NSXIPAddress
        $ovfconfig.common.vsm_netmask_0.value = $global:NSXNetmask
        $ovfconfig.common.vsm_gateway_0.value = $global:NSXGateway
		$ovfconfig.common.vsm_dns1_0.value = $global:DnsServer1 + "," + $global:DnsServer2
		$ovfconfig.common.vsm_ntp_0.value = $global:ntp
        $ovfconfig.common.vsm_domain_0.value = $global:domainname
        $ovfconfig.common.vsm_isSSHEnabled.value = $true
        $ovfconfig.common.vsm_isCEIPEnabled.value = $false
        $ovfconfig.common.vsm_cli_passwd_0.value = $global:NSXUIPassword
        $ovfconfig.common.vsm_cli_en_passwd_0.value = $global:NSXCLIPassword
		$cluster = Get-Cluster -Name $global:VMCluster			
		$vmhost = Get-VMHost -Location $cluster | Where { $_.ConnectionState -eq "Connected" } | Get-Random # Select a connected host
		
		$datastore = Get-Datastore -Name $global:VMDatastore
			
		Write-Host "Deploying NSX VM $global:NSXDisplayName ..."
        $vm = Import-VApp -Source $global:NSXOVA -OvfConfiguration $ovfconfig -Name $global:NSXDisplayName -Location $cluster -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin

		if($global:DeploymentType -eq "Test"){
			Set-VM -VM $vm -NumCpu $global:NSXvCPU -MemoryGB $global:NSXvMEM -Confirm:$false
		}
		
        Write-Host "Powering On $global:NSXDisplayName ..."
        $vm | Start-Vm -RunAsync | Out-Null
		
		Write-Host "NSX Manager services are starting..."
		
		Start-Sleep 300
				
		return $true
		}
		
}

Function ConfigureNSXManager {

	$vm = Get-VM -name $global:NSXDisplayName
	
	if($vm.PowerState -eq "PoweredOff") {
        Write-Host -ForegroundColor Red "NSX Manager VM is not powered on, exiting..."
        exit
	}

	try {
	 
	 Write-Host "   -> Connecting NSX Manager..."
	 
		if(!(Connect-NSXServer -Server $global:NSXHostname -Username admin -Password $global:NSXUIPassword -DisableVIAutoConnect -WarningAction SilentlyContinue)) {
			Write-Host -ForegroundColor Red "Unable to connect to NSX Manager, please check the deployment"
			exit
		} else {
			Write-Host "Successfully logged into NSX Manager $global:NSXHostname..."
		}
	
	}
	
	catch {
        Throw  "Error while connecting NSX Manager"
	}  

		# Configure deployment parameters
		$cluster = Get-Cluster -Name $global:VMCluster -errorAction Stop		
		$datastore = Get-Datastore -Name $global:VMDatastore -errorAction Stop
		$PortGroup = Get-VdPortGroup $global:ControllerNetworkPortGroupName -errorAction Stop
		
		$NSXManagerTimeSettings = Get-NsxManagerTimeSettings
		$NSXManagerTime = $NSXManagerTimeSettings.datetime
		$VIServerTime = $viConnection.ExtensionData.CurrentTime()
		
		write-host -foregroundcolor Yellow "NSX Manager Time : $NSXManagerTime"
		write-host -foregroundcolor Yellow "vCenter Time	 : $VIServerTime"
		
			if($NSXManagerTime -ne $VIServerTime){
				write-host -foregroundcolor red "There is a time difference between NSX Manager and vCenter. Registration may fail ..."
			}		
		
		# Configure syslog and vCenter registration
	    write-host -foregroundcolor green "Configuring NSX Manager`n"

			if ($global:sysLogServer ) {
				Write-Host "   -> Performing NSX Manager Syslog configuration..."
				Set-NsxManager -SyslogServer $global:sysLogServerName -SyslogPort $global:sysLogServerPort -SyslogProtocol "UDP" | out-null
			}
			
        Write-Host "   -> Performing NSX Manager SSO configuration..."
        Set-NsxManager -SsoServer $PSCServer -SsoUserName $global:NSXssoUsername -SsoPassword $global:NSXssoPassword | out-null

        Write-Host "   -> Performing NSX Manager vCenter registration with account $global:NSXssoUsername ..."
        Set-NsxManager -vCenterServer $VIServer -vCenterUserName $global:NSXssoUsername -vCenterPassword $global:NSXssoPassword | out-null

		 # Install NSX License
		write-host -foregroundcolor Green "Installing NSX License..."
		
		$ServiceInstance = Get-View ServiceInstance
        $LicenseManager = Get-View $ServiceInstance.Content.licenseManager
        $LicenseAssignmentManager = Get-View $LicenseManager.licenseAssignmentManager
		$CheckLicense = $LicenseAssignmentManager.QueryAssignedLicenses("nsx-netsec") 
		$LicenseKey=$CheckLicense.AssignedLicense.LicenseKey
		
		if($LicenseKey -ne $global:NsxlicenseKey){
			$LicenseAssignmentManager.UpdateAssignedLicense("nsx-netsec",$global:NsxlicenseKey,$NULL)
		}
		else {
			write-host -foregroundcolor Green "NSX License is already installed ..."
		}
		
		write-host -foregroundcolor Green "Complete`n"
	
		# Deploy Controllers
		
		$ControllerCount = Get-NSXController -ErrorAction silentlycontinue
		
		if((($global:DeploymentType -eq "test") -and ($ControllerCount.Count -eq 0)) -or (($global:DeploymentType -eq "prod") -and ($ControllerCount.Count -eq 0)))
		
		{
		
			write-host -foregroundcolor Green "Deploying NSX Controllers..."
			
			 try {
			 	
				$ControllerPool = Get-NsxIpPool -Name "Controller Pool"
				
				if(!$ControllerPool){		 
					write-host "   -> Creating IP Pool for Controller addressing"
					$ControllerPool = New-NsxIpPool -Name "Controller Pool" -Gateway $global:ControllerNetworkGateway -SubnetPrefixLength $global:ControllerNetworkSubnetPrefixLength -StartAddress $global:ControllerPoolStartIp -EndAddress $global:ControllerPoolEndIp 
				}
				
				for ( $i=1; $i -le $global:NumberOfController; $i++ ) {

					write-host "   -> Deploying NSX Controller $($i)"

					$Controller = New-NsxController -IpPool $ControllerPool -Cluster $cluster -datastore $datastore -PortGroup $PortGroup  -password $global:ControllerPassword -confirm:$false -wait
			 
					write-host "   -> Controller $($i) online."
				}
				
				
			}
			catch {

			Throw  "Failed deploying controller Cluster.  $_"
			}
		}
		
		# Create anti-affinity rule for prod installation
 
		 if(($global:VMHostCount -ge 3) -and ($global.deployment -eq "prod"))
		 
		 {
		 write-host "   -> Creating Anti Affinity Rules for Controllers"
		 $antiAffinityVMs = Get-VM -Name "NSX_Controller*"
		 New-DrsRule -Cluster $global:VMCluster -Name SeperateControllers -KeepTogether $false -VM $antiAffinityVMs
		 } 
		 
		# Prep VDS 
		write-host -foregroundcolor Green "Configuring VDS for use with NSX..." 
		$MgmtVds = Get-VdSwitch $global:MgmtVdsName -errorAction Stop

		#This is assuming two or more NICs on the uplink PG on this VDS.  No LAG required, and results in load balance accross multiple uplink NICs 
        New-NsxVdsContext -VirtualDistributedSwitch $MgmtVds -Teaming "LOADBALANCE_SRCID" -Mtu $global:VxlanMtuSize | out-null 
     
		write-host -foregroundcolor Green "Complete`n" 
		
		 # Prep Clusters 
 
 		write-host -foregroundcolor Green "Preparing clusters to run NSX..." 
	 
		write-host "   -> Creating IP Pools for VTEP addressing" 
 
		$MgmtVtepPool = Get-NsxIpPool -Name "Vtep Pool 01"
		
		if(!$MgmtVtepPool){		
 
        $MgmtVtepPool = New-NsxIpPool -Name "Vtep Pool 01" -Gateway $global:MgmtVdsVxlanNetworkGateway -SubnetPrefixLength $global:MgmtVdsVxlanNetworkSubnetPrefixLength -DnsServer1 $global:DnsServer1 -DnsServer2 $global:DnsServer2 -DnsSuffix $global:DnsSuffix -StartAddress $global:MgmtVdsVtepPoolStartIp -EndAddress $global:MgmtVdsVtepPoolEndIp 
		}
 
         write-host "   -> Preparing cluster and configuring VXLAN." 
         Get-Cluster $cluster | New-NsxClusterVxlanConfig -VirtualDistributedSwitch $MgmtVds -Vlan $global:MgmtVdsVxlanVlanID -VtepCount $global:MgmtVdsHostVtepCount -ipPool $MgmtVtepPool -VxlanPrepTimeout 300 | out-null 
 
 
      write-host -foregroundcolor Green "Complete`n"
	  	
	  ############################## 
      # Configure Segment Pool 
	  
	 $NsxSegmentIdRange = Get-NsxSegmentIdRange -Name "SegmentIDPool" -ErrorAction silentlycontinue
 
	 if(!$NsxSegmentIdRange){		
 
		 write-host -foregroundcolor Green "Configuring SegmentId Pool..." 

		 try {  
			 write-host "   -> Creating Segment Id Pool." 
			 New-NsxSegmentIdRange -Name "SegmentIDPool" -Begin $global:SegmentPoolStart -end $global:SegmentPoolEnd | out-null 
		 } 
		 catch { 
			 Throw  "Failed configuring SegmentId Pool.  $_" 
		 } 
	  
		 write-host -foregroundcolor Green "Complete`n" 
	 }
 
      ############################## 
     # Create Transport Zone 
  
     write-host -foregroundcolor Green "Configuring Transport Zone..." 
 
     try { 
 
         write-host "   -> Creating Transport Zone $TransportZoneName." 
         #Configure TZ and add clusters. 
         New-NsxTransportZone -Name $global:TransportZoneName -Cluster $cluster -ControlPlaneMode "UNICAST_MODE" | out-null 
  
     } 
     catch { 
         Throw  "Failed configuring Transport Zone.  $_" 
  
     } 
	 
	 write-host -foregroundcolor Green "Complete`n" 
	 
	 #Adding vCenter to DFW Exclusion List 
	<#  $VMexclusion=Get-VM -name $global:vCenter
	 Add-NsxFirewallExclusionListMember -VirtualMachine $VMexclusion #>
	 
	 ###################################### 
     #Logical Switches 
 
	# Creates four logical switches 
	
     write-host -foregroundcolor "Green" "Creating Logical Switches..." 
 
		if (Get-NsxLogicalSwitch $global:WebLsName) {
            $WebLs = Get-NsxLogicalSwitch $global:WebLsName
			write-host -foregroundcolor "Yellow" "	$global:WebLsName is already exist..."
		}
		else {
			$WebLs = Get-NsxTransportZone | New-NsxLogicalSwitch $global:WebLsName
		}
        if (Get-NsxLogicalSwitch $global:AppLsName) {
             $AppLs = Get-NsxLogicalSwitch $global:AppLsName
			 write-host -foregroundcolor "Yellow" "	$global:AppLsName is already exist..."
        }
		else {	
			$AppLs = Get-NsxTransportZone | New-NsxLogicalSwitch $global:AppLsName
		}
        if (Get-NsxLogicalSwitch $global:DbLsName) {
            $DbLs = Get-NsxLogicalSwitch $global:DbLsName
			write-host -foregroundcolor "Yellow" "	$global:DbLsName is already exist..."
        }
		else {
			$DbLs = Get-NsxTransportZone | New-NsxLogicalSwitch $global:DbLsName
		}
        if (Get-NsxLogicalSwitch $global:TransitLsName) {
			$TransitLs = Get-NsxLogicalSwitch $global:TransitLsName   
			write-host -foregroundcolor "Yellow" "	$global:TransitLsName is already exist..."			
        }
		else {
			$TransitLs = Get-NsxTransportZone | New-NsxLogicalSwitch $global:TransitLsName
		}
		if (Get-NsxLogicalSwitch $global:MgmtLsName) {
			$MgmtLs = Get-NsxLogicalSwitch $global:MgmtLsName            
        }
		else {
			$MgmtLs = Get-NsxTransportZone | New-NsxLogicalSwitch $global:MgmtLsName 
		}

	######################################
    # DLR
	
	$Ldr = Get-NsxLogicalRouter -Name "$global:DLRName" -ErrorAction silentlycontinue
	
	if(!$Ldr){
	
		# DLR Appliance has the uplink router interface created first.
		write-host -foregroundcolor "Green" "Creating DLR"
		$LdrvNic0 = New-NsxLogicalRouterInterfaceSpec -type Uplink -Name $global:TransitLsName -ConnectedTo $TransitLs -PrimaryAddress $global:DLRUplinkAddress -SubnetPrefixLength $global:DefaultSubnetBits

			# No need HA for Test environment
			if($global:DeploymentType -eq "Test"){		
				# The DLR is created with the first vnic defined, and the datastore and cluster on which the Control VM will be deployed.
				$Ldr = New-NsxLogicalRouter -name $global:DLRName -interface $LdrvNic0 -ManagementPortGroup $MgmtLs -cluster $cluster -datastore $DataStore			
				
						
			}
			# HA will be enabled for Prod environment			
			if($global:DeploymentType -eq "Prod"){
				write-host -foregroundcolor "Green" "Enabling HA for $global:DLRName"
				# The DLR is created with the first vnic defined, and the datastore and cluster on which the Control VM will be deployed.
				$Ldr = New-NsxLogicalRouter -name $global:DLRName -interface $LdrvNic0 -ManagementPortGroup $MgmtLs  -cluster $cluster -datastore $DataStore -EnableHA
		
			}
					
		# Set DLR Password via XML Element
		$Ldr = Get-NsxLogicalRouter  -name $global:DLRName

		Add-XmlElement -xmlRoot $Ldr.CliSettings -xmlElementName "password" -xmlElementText $global:AppliancePassword 
		$ldr | Set-NsxLogicalRouter -confirm:$false | out-null
		
		# Set DLR SSH service enable
		$Ldr = Get-NsxLogicalRouter  -name $global:DLRName
		$Ldr.CliSettings.remoteAccess= "$true"
		$ldr | Set-NsxLogicalRouter -confirm:$false | out-null
			
		## Adding DLR interfaces after the DLR has been deployed. This can be done any time if new interfaces are required.
		write-host -foregroundcolor Green "Adding Web LIF to DLR"
		$Ldr | New-NsxLogicalRouterInterface -Type Internal -name $global:WebLsName  -ConnectedTo $WebLs -PrimaryAddress $global:DLRWebPrimaryAddress -SubnetPrefixLength $global:DefaultSubnetBits | out-null

		write-host -foregroundcolor Green "Adding App LIF to DLR"
		$Ldr | New-NsxLogicalRouterInterface -Type Internal -name $global:AppLsName  -ConnectedTo $AppLs -PrimaryAddress $global:DLRAppPrimaryAddress -SubnetPrefixLength $global:DefaultSubnetBits | out-null

		write-host -foregroundcolor Green "Adding DB LIF to DLR"
		$Ldr | New-NsxLogicalRouterInterface -Type Internal -name $global:DbLsName  -ConnectedTo $DbLs -PrimaryAddress $global:DLRDbPrimaryAddress -SubnetPrefixLength $global:DefaultSubnetBits | out-null

			if($global:RoutingProtocol -eq "Static"){
			
				## DLR Routing - default route from DLR with a next-hop of the Edge.
				write-host -foregroundcolor Green "Setting default route on DLR to $EdgeInternalAddress"

				##The first line pulls the uplink name coz we cant assume we know the index ID
				$LdrTransitInt = get-nsxlogicalrouter | get-nsxlogicalrouterinterface | ? { $_.name -eq $global:TransitLsName}
				Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -DefaultGatewayVnic $LdrTransitInt.index -DefaultGatewayAddress $global:PLR01InternalAddress -confirm:$false | out-null
			}
		
		## Disable DLR firewall
		$Ldr = get-nsxlogicalrouter $global:DLRName
		$Ldr.features.firewall.enabled = "false"
		$Ldr | Set-nsxlogicalrouter -confirm:$false | out-null

	}
	
    ######################################
    # EDGE

	$Edge1 = Get-NsxEdge -name $global:PLR01Name
		
		if(!$Edge1) {
		
			## Defining the uplink and internal interfaces to be used when deploying the edge. Note there are two IP addresses on these interfaces. $EdgeInternalSecondaryAddress and $EdgeUplinkSecondaryAddress are the VIPs
			$EdgeUplinkNetwork = get-vdportgroup $global:EdgeUplinkNetworkName -errorAction Stop
			$edgevnic0 = New-NsxEdgeinterfacespec -index 0 -Name "Uplink" -type Uplink -ConnectedTo $EdgeUplinkNetwork -PrimaryAddress $global:PLR01UplinkAddress -SubnetPrefixLength $global:DefaultSubnetBits
			$edgevnic1 = New-NsxEdgeinterfacespec -index 1 -Name $global:TransitLsName -type Internal -ConnectedTo $TransitLs -PrimaryAddress $global:PLR01InternalAddress -SubnetPrefixLength $global:DefaultSubnetBits
			## Deploy appliance with the defined uplinks
			write-host -foregroundcolor "Green" "Creating Edge $global:PLR01Name"
			# If Prod deployment disable esg firewall
				if($global:DeploymentType -eq "Prod"){
					$Edge1 = New-NsxEdge -name $global:PLR01Name -hostname $global:PLR01Name -cluster $Cluster -datastore $DataStore -Interface $edgevnic0, $edgevnic1 -Password $global:AppliancePassword -FwEnabled:$false -enablessh
				}
				else{
					$Edge1 = New-NsxEdge -name $global:PLR01Name -hostname $global:PLR01Name -cluster $Cluster -datastore $DataStore -Interface $edgevnic0, $edgevnic1 -Password $global:AppliancePassword -FwDefaultPolicyAllow -enablessh
				}
				
				if($global:RoutingProtocol -eq "Static"){
					##Configure Edge DGW
					Get-NSXEdge $global:PLR01Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -DefaultGatewayAddress $global:PLR01DefaultGW -confirm:$false | out-null
				}
		 }
	 
		 if($global:DeploymentType -eq "Prod"){
		 
			$Edge2 = Get-NsxEdge -name $global:PLR02Name
		
			if(!$Edge2) {
			
				## Defining the uplink and internal interfaces to be used when deploying the edge. Note there are two IP addreses on these interfaces. $EdgeInternalSecondaryAddress and $EdgeUplinkSecondaryAddress are the VIPs
				$EdgeUplinkNetwork = get-vdportgroup $global:EdgeUplinkNetworkName -errorAction Stop
				$edgevnic0 = New-NsxEdgeinterfacespec -index 0 -Name "Uplink" -type Uplink -ConnectedTo $EdgeUplinkNetwork -PrimaryAddress $global:PLR02UplinkAddress -SubnetPrefixLength $global:DefaultSubnetBits
				$edgevnic1 = New-NsxEdgeinterfacespec -index 1 -Name $global:TransitLsName -type Internal -ConnectedTo $TransitLs -PrimaryAddress $global:PLR02InternalAddress -SubnetPrefixLength $global:DefaultSubnetBits
				## Deploy appliance with the defined uplinks
				write-host -foregroundcolor "Green" "Creating Edge $global:PLR02Name"
					if($global:DeploymentType -eq "Prod"){
						$Edge2 = New-NsxEdge -name $global:PLR02Name -hostname $global:PLR02Name -cluster $Cluster -datastore $DataStore -Interface $edgevnic0, $edgevnic1 -Password $global:AppliancePassword -FwEnabled:$false -enablessh
					}
					else{
						$Edge2 = New-NsxEdge -name $global:PLR02Name -hostname $global:PLR02Name -cluster $Cluster -datastore $DataStore -Interface $edgevnic0, $edgevnic1 -Password $global:AppliancePassword -FwDefaultPolicyAllow -enablessh
					}
					
					if($global:RoutingProtocol -eq "Static"){
						##Configure Edge DGW
						Get-NSXEdge $global:PLR01Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -DefaultGatewayAddress $global:PLR01DefaultGW -confirm:$false | out-null
					}
			 }
						 
			write-host "   -> Creating Anti Affinity Rules for PLRs"
			$antiAffinityVMs=Get-VM | Where {$_.name -like "$global:PLR01Name*" -or $_.name -like "$global:PLR02Name*"}
			New-DrsRule -Cluster $global:VMCluster -Name SeperatePLRs -KeepTogether $false -VM $antiAffinityVMs | out-null
		 }
	#####################################
    # OSPF #

	if($global:RoutingProtocol -eq "OSPF"){    
	
		#$Edge1 = Get-NsxEdge $global:PLR01Name
	
		write-host -foregroundcolor Green "Configuring $global:PLR01Name OSPF"
		
		Get-NsxEdge $global:PLR01Name | Get-NsxEdgerouting | set-NsxEdgeRouting -EnableOspf -RouterId $global:PLR01UplinkAddress -EnableEcmp -confirm:$false | out-null

		#Remove the dopey area 51 NSSA - just to show example of complete OSPF configuration including area creation.
		Get-NsxEdge $global:PLR01Name | Get-NsxEdgerouting | Get-NsxEdgeOspfArea -AreaId 51 | Remove-NsxEdgeOspfArea -confirm:$false

		#Create new Area for OSPF
		Get-NsxEdge $global:PLR01Name | Get-NsxEdgerouting | New-NsxEdgeOspfArea -AreaId $global:TransitOspfAreaId -Type normal -confirm:$false | out-null
		
		#Area to interface mapping
		Get-NsxEdge $global:PLR01Name | Get-NsxEdgerouting | New-NsxEdgeOspfInterface -AreaId $global:TransitOspfAreaId -vNic 1 -confirm:$false | out-null

		#$Edge2 = Get-NsxEdge $global:PLR02Name
		write-host -foregroundcolor Green "Configuring $global:PLR02Name OSPF"
		
		Get-NsxEdge $global:PLR02Name | Get-NsxEdgerouting | set-NsxEdgeRouting -EnableOspf -RouterId $global:PLR02UplinkAddress -EnableEcmp -confirm:$false | out-null

		#Remove the dopey area 51 NSSA - just to show example of complete OSPF configuration including area creation.
		Get-NsxEdge $global:PLR02Name | Get-NsxEdgerouting | Get-NsxEdgeOspfArea -AreaId 51 | Remove-NsxEdgeOspfArea -confirm:$false

		#Create new Area 10 for OSPF
		Get-NsxEdge $global:PLR02Name | Get-NsxEdgerouting | New-NsxEdgeOspfArea -AreaId $global:TransitOspfAreaId -Type normal -confirm:$false | out-null
		
		#Area to interface mapping
		Get-NsxEdge $global:PLR02Name | Get-NsxEdgerouting | New-NsxEdgeOspfInterface -AreaId $global:TransitOspfAreaId -vNic 1 -confirm:$false | out-null
		
		write-host -foregroundcolor Green "Configuring DLR OSPF"
		Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting | set-NsxLogicalRouterRouting -EnableOspf -EnableOspfRouteRedistribution -RouterId $global:DLRUplinkAddress -ProtocolAddress $global:DLR01ProtocolAddress -ForwardingAddress $global:DLRUplinkAddress -confirm:$false | out-null

		#Remove the dopey area 51 NSSA - just to show example of complete OSPF configuration including area creation.
		Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfArea -AreaId 51 | Remove-NsxLogicalRouterOspfArea -confirm:$false

		#Create new Area
		Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfArea -AreaId $global:TransitOspfAreaId -Type normal -confirm:$false | out-null

		#Area to interface mapping
		$LdrTransitInt = get-nsxlogicalrouter | get-nsxlogicalrouterinterface | ? { $_.name -eq $global:TransitLsName}
		Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfInterface -AreaId $global:TransitOspfAreaId -vNic $LdrTransitInt.index -confirm:$false | out-null
	
		write-host -foregroundcolor Green "Configuring Route Redistribution"
		Get-NsxLogicalRouter $global:DLRName | Set-NsxLogicalRouterRouting -EnableBgpRouteRedistribution:$false -confirm:$false
		Get-NsxLogicalRouter $global:DLRName | Set-NsxLogicalRouterRouting -EnableBgpRouteRedistribution:$true -confirm:$false
		Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule -Learner bgp | Remove-NsxLogicalRouterRedistributionRule -Confirm:$false
 		Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterRedistributionRule -Learner ospf -FromConnected -Action permit -confirm:$false
		
		
	}
	
	#####################################
    # BGP #

	if($global:RoutingProtocol -eq "BGP"){    
	
		write-host -foregroundcolor Green "Configuring $global:PLR01Name BGP"		
		$rtg = Get-NsxEdge $global:PLR01Name | Get-NsxEdgeRouting
		$rtg | Set-NsxEdgeRouting -EnableEcmp -EnableBgp -RouterId $global:PLR01InternalAddress -LocalAS $global:iBGPAS -Confirm:$false | out-null

		$rtg = Get-NsxEdge $global:PLR01Name | Get-NsxEdgeRouting			
		$rtg | New-NsxEdgeBgpNeighbour -IpAddress $global:DLR01ProtocolAddress -RemoteAS $global:iBGPAS -KeepAliveTimer $global:BGPKeepAliveTimer -HoldDownTimer $global:BGPHoldDownTimer  -confirm:$false | out-null
		$rtg = Get-NsxEdge $global:PLR01Name | Get-NsxEdgeRouting	
		$rtg | New-NsxEdgeBgpNeighbour -IpAddress $global:PLReBGPNeigbour1 -RemoteAS $global:eBGPAS -KeepAliveTimer $global:BGPKeepAliveTimer -HoldDownTimer $global:BGPHoldDownTimer  -confirm:$false | out-null
		
		$rtg = Get-NsxEdge $global:PLR01Name | Get-NsxEdgeRouting		
		$rtg | Set-NsxEdgeBgp -GracefulRestart:$false -Confirm:$false | out-null
 
		write-host -foregroundcolor Green "Configuring $global:PLR02Name BGP"
		$rtg = Get-NsxEdge $global:PLR02Name | Get-NsxEdgeRouting
		$rtg | Set-NsxEdgeRouting -EnableEcmp -EnableBgp -RouterId $global:PLR02InternalAddress -LocalAS $global:iBGPAS -Confirm:$false | out-null
		
		$rtg = Get-NsxEdge $global:PLR02Name | Get-NsxEdgeRouting
		$rtg | New-NsxEdgeBgpNeighbour -IpAddress $global:DLR01ProtocolAddress -RemoteAS $global:iBGPAS -KeepAliveTimer $global:BGPKeepAliveTimer -HoldDownTimer $global:BGPHoldDownTimer  -confirm:$false | out-null
		$rtg = Get-NsxEdge $global:PLR02Name | Get-NsxEdgeRouting
		$rtg | New-NsxEdgeBgpNeighbour -IpAddress $global:PLReBGPNeigbour1 -RemoteAS $global:eBGPAS -KeepAliveTimer $global:BGPKeepAliveTimer -HoldDownTimer $global:BGPHoldDownTimer  -confirm:$false | out-null
					
	    $rtg = Get-NsxEdge $global:PLR02Name | Get-NsxEdgeRouting
		$rtg | Set-NsxEdgeBgp -GracefulRestart:$false -Confirm:$false | out-null
		
		write-host -foregroundcolor Green "Configuring Floating Static Routes"
		
		$s = $global:DLRWebPrimaryAddress.split(".")
		$DLRWebStaticRoute = $s[0]+"."+$s[1]+"."+$s[2]+".0/"+$global:DefaultSubnetBits
		
		$s = $global:DLRAppPrimaryAddress.split(".")
		$DLRAppStaticRoute = $s[0]+"."+$s[1]+"."+$s[2]+".0/"+$global:DefaultSubnetBits
		
		$s = $global:DLRDBPrimaryAddress.split(".")
		$DLRDBStaticRoute = $s[0]+"."+$s[1]+"."+$s[2]+".0/"+$global:DefaultSubnetBits
		
		Get-NsxEdge $global:PLR01Name | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network $DLRWebStaticRoute -NextHop $global:DLR01ProtocolAddress -AdminDistance 250 -confirm:$false | out-null
		Get-NsxEdge $global:PLR01Name | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network $DLRAppStaticRoute -NextHop $global:DLR01ProtocolAddress -AdminDistance 250 -confirm:$false | out-null
		Get-NsxEdge $global:PLR01Name | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network $DLRDBStaticRoute -NextHop $global:DLR01ProtocolAddress -AdminDistance 250 -confirm:$false | out-null
		Get-NsxEdge $global:PLR02Name | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network $DLRWebStaticRoute -NextHop $global:DLR01ProtocolAddress -AdminDistance 250 -confirm:$false | out-null
		Get-NsxEdge $global:PLR02Name | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network $DLRAppStaticRoute -NextHop $global:DLR01ProtocolAddress -AdminDistance 250 -confirm:$false | out-null
		Get-NsxEdge $global:PLR02Name | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network $DLRDBStaticRoute -NextHop $global:DLR01ProtocolAddress -AdminDistance 250 -confirm:$false | out-null
  	  	
		write-host -foregroundcolor Green "Configuring DLR BGP"
		Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting | set-NsxLogicalRouterRouting -EnableEcmp -EnableBgp -RouterId $global:DLRUplinkAddress -LocalAS $iBGPAS -ProtocolAddress $global:DLR01ProtocolAddress -ForwardingAddress $global:DLRUplinkAddress -confirm:$false | out-null

		$rtg = Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting
         
		Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterBgpNeighbour -IpAddress $global:PLR01InternalAddress -RemoteAS $global:iBGPAS -ProtocolAddress $global:DLR01ProtocolAddress -ForwardingAddress $global:DLRUplinkAddress  -KeepAliveTimer $global:BGPKeepAliveTimer -HoldDownTimer $global:BGPHoldDownTimer -confirm:$false | out-null
		Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterBgpNeighbour -IpAddress $global:PLR02InternalAddress -RemoteAS $global:iBGPAS -ProtocolAddress $global:DLR01ProtocolAddress -ForwardingAddress $global:DLRUplinkAddress  -KeepAliveTimer $global:BGPKeepAliveTimer -HoldDownTimer $global:BGPHoldDownTimer -confirm:$false | out-null
		
		write-host -foregroundcolor Green "Configuring Route Redistribution"
		Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableOspfRouteRedistribution:$false -confirm:$false | out-null
		Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableBgpRouteRedistribution:$true -confirm:$false | out-null
		Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule -Learner ospf | Remove-NsxLogicalRouterRedistributionRule -Confirm:$false | out-null
 		Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterRedistributionRule -Learner bgp -FromConnected -Action permit -confirm:$false | out-null
		
		Get-NsxEdge $global:PLR01Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableOspfRouteRedistribution:$false -confirm:$false | out-null
		Get-NsxEdge $global:PLR01Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableBgpRouteRedistribution:$true -confirm:$false | out-null
		Get-NsxEdge $global:PLR01Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -Learner ospf | Remove-NsxEdgeRedistributionRule -Confirm:$false | out-null
 		Get-NsxEdge $global:PLR01Name | Get-NsxEdgeRouting | New-NsxEdgeRedistributionRule -Learner bgp -FromConnected -FromStatic -Action permit -confirm:$false | out-null
		
		Get-NsxEdge $global:PLR02Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableOspfRouteRedistribution:$false -confirm:$false | out-null
		Get-NsxEdge $global:PLR02Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableBgpRouteRedistribution:$true -confirm:$false | out-null
		Get-NsxEdge $global:PLR02Name | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -Learner ospf | Remove-NsxEdgeRedistributionRule -Confirm:$false | out-null
 		Get-NsxEdge $global:PLR02Name | Get-NsxEdgeRouting | New-NsxEdgeRedistributionRule -Learner bgp -FromConnected -FromStatic -Action permit -confirm:$false | out-null
		
		write-host -foregroundcolor Green "Disabling Graceful Restart"
		$rtg = Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting
        $rtg | Set-NsxLogicalRouterBgp -GracefulRestart:$false -confirm:$false | out-null
  
	}
	
     write-host -foregroundcolor Green "`nNSX Infrastructure Configuration Complete`n" 
 		
     Disconnect-NsxServer
}
	
NSX-Deployment-Precheck

$title = "Confirm NSX Manager Deployment"
$message = "Do you want to continue NSX Deployment"

$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", `
	"Deploys and Configures NSX Components"
 
$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", `
    exit

$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

$result = $host.ui.PromptForChoice($title, $message, $options, 0) 

switch ($result)
    {
        0 {
			$StartTime = Get-Date
			DeployNSXManager
				if(DeployNSXManager -eq $true){
					ConfigureNSXManager
					$EndTime = Get-Date
					$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)
					write-host "Duration: $duration minutes"
				}
			Disconnect-VIServer $viConnection -Confirm:$false
		}
        1 {"Deployment is canceled"
			Disconnect-VIServer $viConnection -Confirm:$false
		}
    }

	
	
