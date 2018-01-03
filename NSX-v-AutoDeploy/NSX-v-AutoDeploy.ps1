# Author: Hakan Akkurt
$ScriptVersion = "1.1"

# Deployment Parameters
$VIServer = "vcsa-01a.corp.local"
$PSCServer = "vcsa-01a.corp.local"
$VIUsername = "administrator@vsphere.local"
$VIPassword = "VMware1!"
$verboseLogFile = "ScriptLogs.log"
$global:DnsServer1 = "192.168.110.10"
$global:DnsServer2 = "192.168.110.10"
$global:DnsSuffix = "corp.local"
$global:ntp = "192.168.110.10"

# NSX Manager Configuration
$global:NSXOVA =  "C:\Scripts\VMware-NSX-Manager-6.3.4-6845891.ova"
$global:VMNetwork = "VM-RegionA01-vDS-MGMT"
$global:NSXDisplayName = "nsxmgr-01a"
$global:NSXHostname = "nsxmgr-01a.corp.local"
$global:NSXIPAddress = "192.168.110.42"
$global:NSXNetmask = "255.255.255.0"
$global:NSXGateway = "192.168.110.1"
$global:NSXUIPassword = "VMware1!"
$global:NSXCLIPassword = "VMware1!"
$global:VMDatastore = "RegionA01-ISCSI01-COMP01"
$global:VMCluster = "RegionA01-MGMT01"
$global:NSXssoUsername = "administrator@vsphere.local"
$global:NSXssoPassword = "VMware1!"
$global:NsxlicenseKey = ""
$global:ControllerPoolStartIp = "192.168.110.202"
$global:ControllerPoolEndIp = "192.168.110.204"
$global:ControllerPoolEndIp = "192.168.110.204"
$global:ControllerNetworkSubnetMask = "255.255.255.0"
$global:ControllerNetworkSubnetPrefixLength ="24"
$global:ControllerNetworkGateway = "192.168.110.1"
$global:ControllerNetworkPortGroupName = "VM-RegionA01-vDS-MGMT"
$global:EdgeUplinkNetworkName = "VM-RegionA01-vDS-MGMT"
$global:ControllerDatastore = "RegionA01-ISCSI01-COMP01"
$global:ControllerPassword = "VMware1!VMware1!"
$global:SegmentPoolStart = "5000"
$global:SegmentPoolEnd = "5999"
$global:TransportZoneName = "TZ01"
$global:VxlanMtuSize = 1600 
$global:MgmtVdsName = "RegionA01-vDS-MGMT"
$global:MgmtVdsVxlanNetworkSubnetMask = "255.255.255.0" 
$global:MgmtVdsVxlanNetworkSubnetPrefixLength = "24" 
$global:MgmtVdsVxlanNetworkGateway = "192.168.110.1" 
$global:MgmtVdsVxlanVlanID = "0" 
$global:MgmtVdsHostVtepCount = 1 
$global:MgmtVdsVtepPoolStartIp = "192.168.110.141" 
$global:MgmtVdsVtepPoolEndIp = "192.168.110.151" 

# Logical Switches / Router Names 
$global:TransitLsName = "Transit" 
$global:WebLsName = "LS-Web" 
$global:AppLsName = "LS-App" 
$global:DbLsName = "LS-DB" 
$global:MgmtLsName = "LS-Mgmt"
$global:EdgeHALsName = "LS-HA"
$global:PLR1Name = "PLR01"
$global:PLR2Name = "PLR02" 
$global:DLRName = "DLR01" 

# Routing Topology 
$global:PLR01InternalAddress = "172.16.1.1" 
$global:PLR01UplinkAddress = "192.168.110.121" 
$global:PLR01DefaultGW = "192.168.110.1"
$global:PLR01Size = "Large"
$global:PLR02InternalAddress = "172.16.1.2" 
$global:PLR02UplinkAddress = "192.168.110.122" 
$global:PLR02DefaultGW = "192.168.110.1"
$global:PLR02Size = "Large"
$global:DLRUplinkAddress = "172.16.1.3"
$global:DLR01ProtocolAddress = "172.16.1.4" 
$global:DLRWebPrimaryAddress = "10.0.1.1" 
$global:DLRAppPrimaryAddress = "10.0.2.1" 
$global:DLRDbPrimaryAddress = "10.0.3.1" 
$global:DefaultSubnetMask = "255.255.255.0" 
$global:DefaultSubnetBits = "24" 
$global:AppliancePassword = "VMware1!VMware1!"
$global:RoutingProtocol = "OSPF" # Select OSPF, BGP or Static
$global:TransitOspfAreaId = "10"
$global:iBGPAS = "65531" 
$global:eBGPAS = "65532"

$global:NSXvCPU = "2" # Reconfigure NSX vCPU
$global:NSXvMEM = "8" # Reconfigure NSX vMEM (GB)
$global:NumberOfController = "1"

# Parameter initial values

$global:domainname = $null
$global:sysLogServer = $null
$global:sysLogServerName = $null
$global:sysLogServerPort = $null
$global:NSXManagerDeployed = $false
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

	Write-Host -ForegroundColor Blue "Starting NSX Auto Deploy Script version $ScriptVersion"

# Check OVA and PowerNSX
	
	if(!(Test-Path $global:NSXOVA)) {
		Write-Host -ForegroundColor Red "`nUnable to find $NSXOVA ...`nexiting"
		exit
	}

	#Load the VMware PowerCLI tools - no PowerCLI is fatal. 

	if(-not (Get-Module -Name "VMware.VimAutomation.Core")) {
		$title = ""
		
		$message = "No PowerCLI found. Do you want to continue ?"

		$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", `
			"PowerCli module check"
		 
		$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", `
			exit

		$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

		$result = $host.ui.PromptForChoice($title, $message, $options, 1) 

		switch ($result)
			{
				0 {	}
				1 {exit}
			}
	
		
	}
	
	if(-not (Get-Module -Name "PowerNSX")) {
		
		$title = ""
		
		$message = "No PowerNSX found. Do you want to continue ? "
		
		$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", `
			"Power NSX module check"
		 
		$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", `
			exit

		$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

		$result = $host.ui.PromptForChoice($title, $message, $options, 1) 

		switch ($result)
			{
				0 {	}
				1 {exit}
			}
		
	}
	
	Do {
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
	}

$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue

# Deployment Precheck    
Function NSX-Deployment-Precheck {
	
	$Datacenters=Get-Datacenter

	Write-Host -ForegroundColor blue "Precheck Started"		
	
		foreach ($Datacenter in $Datacenters) {
				
			$DatacenterName = $Datacenter.name
			#Write-Host -ForegroundColor Yellow "Datacenter Name : "$DatacenterName
			$Clusters = Get-Cluster -Location $Datacenter
				
				foreach ($Cluster in $Clusters) {
					
					$ClusterName = $Cluster.name					
					Write-Host -ForegroundColor yellow "$ClusterName DRS status =" $Cluster.DRSEnabled - $Cluster.DRSAutomationLevel
					$VMHosts=Get-VMHost -Location $ClusterName
					
						foreach ($VMHost in $VMHosts) {
							
							$VMHostName = $VMHost.name		
							$VMHostMemory=$VMHost.MemoryTotalGB
							$VMHostCPU=$VMHost.NumCpu		
							$ClusterisCompatible = $false	
							
							#Write-Host -ForegroundColor White "		Host:" $VMHostName
							
							if ($VMHostMemory -ge 8) {
									$ClusterisCompatible = $true
								}
								
							if ($VMHostCPU -ge 4) {
								
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
						
							if($ClusterName -contains $global:VMCluster) {
							
							$global:VMHostCount = (Get-Cluster $global:VMCluster | Get-VMHost).count
							
								if (!$ClusterisCompatible) {
										Write-Host -ForegroundColor red "$ClusterName has not sufficient resources for NSX Components Deployment"		
								}
								else {
									Write-Host -ForegroundColor yellow "$ClusterName has sufficient resources for NSX Components Deployment"	
								}
							}
						}
							
		}
		Write-Host -ForegroundColor yellow "Deployment Type :" $global:DeploymentType
		<# Write-Host -ForegroundColor yellow "NTP Servers :" $ntp
		Write-Host -ForegroundColor yellow "DNS Servers :" $dns
		Write-Host -ForegroundColor yellow "Domain Name :" $domainname
		Write-Host -ForegroundColor yellow "Syslog Server :" $sysLogServer #>
		Write-Host -ForegroundColor blue "Precheck Completed"	
}

Function DeployNSXManager {
	# Deploy NSX Manager 

		$NSXManagerVmName = Get-VM -name $global:NSXDisplayName -ErrorAction silentlycontinue
		
		if($NSXManagerVmName){
			Write-Host -ForegroundColor Red "NSX Manager is already deployed"
				$global:NSXManagerDeployed = $true
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
		
		Start-Sleep 180
				
		$global:NSXManagerDeployed = $true
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
		write-host -foregroundcolor Yellow "vCenter Time : $VIServerTime"
		
			if($NSXManagerTime -ne $VIServerTime){
				write-host -foregroundcolor red "There is a time difference between NSX Manager and vCenter. Registration may fail ..."
			}		
		
		# Configure syslog and vCenter registration
	    write-host -foregroundcolor Green "Configuring NSX Manager`n"

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
		
		# Create anti-affinity rule for prod installatin
 
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
         Get-Cluster $cluster | New-NsxClusterVxlanConfig -VirtualDistributedSwitch $MgmtVds -Vlan $global:MgmtVdsVxlanVlanID -VtepCount $global:MgmtVdsHostVtepCount -ipPool $MgmtVtepPool| out-null 
 
 
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
	 
	 #Adding vCenter to DFW Exclusion List 
	<#  $VMexclusion=Get-VM -name $global:vCenter
	 Add-NsxFirewallExclusionListMember -VirtualMachine $VMexclusion #>
	 
	 ###################################### 
     #Logical Switches 
 
	# Creates four logical switches 
	
     write-host -foregroundcolor "Green" "Creating Logical Switches..." 
 
		if (Get-NsxLogicalSwitch $global:WebLsName) {
            $WebLs = Get-NsxLogicalSwitch $global:WebLsName
			write-host -foregroundcolor "Yellow" "$global:WebLsName is already exist..."
		}
		else {
			$WebLs = Get-NsxTransportZone | New-NsxLogicalSwitch $global:WebLsName
		}
        if (Get-NsxLogicalSwitch $global:AppLsName) {
             $AppLs = Get-NsxLogicalSwitch $global:AppLsName
			 write-host -foregroundcolor "Yellow" "$global:AppLsName is already exist..."
        }
		else {	
			$AppLs = Get-NsxTransportZone | New-NsxLogicalSwitch $global:AppLsName
		}
        if (Get-NsxLogicalSwitch $global:DbLsName) {
            $DbLs = Get-NsxLogicalSwitch $global:DbLsName
			write-host -foregroundcolor "Yellow" "$global:DbLsName is already exist..."
        }
		else {
			$DbLs = Get-NsxTransportZone | New-NsxLogicalSwitch $global:DbLsName
		}
        if (Get-NsxLogicalSwitch $global:TransitLsName) {
			$TransitLs = Get-NsxLogicalSwitch $global:TransitLsName   
			write-host -foregroundcolor "Yellow" "$global:TransitLsName is already exist..."			
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
		

	# $EdgeHALs = Get-NsxTransportZone | New-NsxLogicalSwitch $global:EdgeHALsName
     

	######################################
    # DLR
	
	$Ldr = Get-NsxLogicalRouter -Name "$global:DLRName" -ErrorAction silentlycontinue
	
	if(!$ldr){
	
		# DLR Appliance has the uplink router interface created first.
		write-host -foregroundcolor "Green" "Creating DLR"
		$LdrvNic0 = New-NsxLogicalRouterInterfaceSpec -type Uplink -Name $global:TransitLsName -ConnectedTo $TransitLs -PrimaryAddress $global:DLRUplinkAddress -SubnetPrefixLength $global:DefaultSubnetBits

		if($global:DeploymentType -eq "Test"){
		
			# The DLR is created with the first vnic defined, and the datastore and cluster on which the Control VM will be deployed.
			$Ldr = New-NsxLogicalRouter -name $global:DLRName -interface $LdrvNic0 -ManagementPortGroup $MgmtLs  -cluster $cluster -datastore $DataStore
		}
	
		if($global:DeploymentType -eq "Prod"){
			write-host -foregroundcolor "Green" "Enabling HA for $global:DLRName"
			# The DLR is created with the first vnic defined, and the datastore and cluster on which the Control VM will be deployed.
			$Ldr = New-NsxLogicalRouter -name $global:DLRName -interface $LdrvNic0 -ManagementPortGroup $MgmtLs  -cluster $cluster -datastore $DataStore -EnableHA
		}
		
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

	$Edge1 = Get-NsxEdge -name $global:PLR1Name
	
	if(!$Edge1) {
	
		## Defining the uplink and internal interfaces to be used when deploying the edge. Note there are two IP addreses on these interfaces. $EdgeInternalSecondaryAddress and $EdgeUplinkSecondaryAddress are the VIPs
		$EdgeUplinkNetwork = get-vdportgroup $global:EdgeUplinkNetworkName -errorAction Stop
		$edgevnic0 = New-NsxEdgeinterfacespec -index 0 -Name "Uplink" -type Uplink -ConnectedTo $EdgeUplinkNetwork -PrimaryAddress $global:PLR01UplinkAddress -SubnetPrefixLength $global:DefaultSubnetBits
		$edgevnic1 = New-NsxEdgeinterfacespec -index 1 -Name $global:TransitLsName -type Internal -ConnectedTo $TransitLs -PrimaryAddress $global:PLR01InternalAddress -SubnetPrefixLength $global:DefaultSubnetBits
		## Deploy appliance with the defined uplinks
		write-host -foregroundcolor "Green" "Creating Edge $global:PLR1Name"
		# If Prod deployment disable esg firewall
		if($global:DeploymentType -eq "Prod"){
			$Edge1 = New-NsxEdge -name $global:PLR1Name -cluster $Cluster -datastore $DataStore -Interface $edgevnic0, $edgevnic1 -Password $global:AppliancePassword -FwEnabled:$false
		}
		else{
			$Edge1 = New-NsxEdge -name $global:PLR1Name -cluster $Cluster -datastore $DataStore -Interface $edgevnic0, $edgevnic1 -Password $global:AppliancePassword -FwDefaultPolicyAllow
		}
		
		if($global:RoutingProtocol -eq "Static"){
			##Configure Edge DGW
			Get-NSXEdge $global:PLR1Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -DefaultGatewayAddress $global:PLR01DefaultGW -confirm:$false | out-null
		}
	 }
	 
	 if($global:DeploymentType -eq "Prod"){
	 
		$Edge2 = Get-NsxEdge -name $global:PLR2Name
	
		if(!$Edge2) {
		
			## Defining the uplink and internal interfaces to be used when deploying the edge. Note there are two IP addreses on these interfaces. $EdgeInternalSecondaryAddress and $EdgeUplinkSecondaryAddress are the VIPs
			$EdgeUplinkNetwork = get-vdportgroup $global:EdgeUplinkNetworkName -errorAction Stop
			$edgevnic0 = New-NsxEdgeinterfacespec -index 0 -Name "Uplink" -type Uplink -ConnectedTo $EdgeUplinkNetwork -PrimaryAddress $global:PLR02UplinkAddress -SubnetPrefixLength $global:DefaultSubnetBits
			$edgevnic1 = New-NsxEdgeinterfacespec -index 1 -Name $global:TransitLsName -type Internal -ConnectedTo $TransitLs -PrimaryAddress $global:PLR02InternalAddress -SubnetPrefixLength $global:DefaultSubnetBits
			## Deploy appliance with the defined uplinks
			write-host -foregroundcolor "Green" "Creating Edge $global:PLR2Name"
			$Edge2 = New-NsxEdge -name $global:PLR2Name -cluster $Cluster -datastore $DataStore -Interface $edgevnic0, $edgevnic1 -Password $global:AppliancePassword -fwenabled:$false
			
			if($global:RoutingProtocol -eq "Static"){
				##Configure Edge DGW
				Get-NSXEdge $global:PLR2Name | Get-NsxEdgeRouting | Set-NsxEdgeRouting -DefaultGatewayAddress $global:PLR02DefaultGW -confirm:$false | out-null
			}
		 }
		 			 
		write-host "   -> Creating Anti Affinity Rules for PLRs"
		$antiAffinityVMs = Get-VM -Name "PLR*"
		New-DrsRule -Cluster $global:VMCluster -Name SeperatePLRs -KeepTogether $false -VM $antiAffinityVMs | out-null
	 }
	 ####################################
    # OSPF

	if($global:RoutingProtocol -eq "OSPF"){
	
		#$Edge1 = Get-NsxEdge $global:PLR1Name
	
		write-host -foregroundcolor Green "Configuring $global:PLR1Name OSPF"
		
		Get-NsxEdge $global:PLR1Name | Get-NsxEdgerouting | set-NsxEdgeRouting -EnableOspf -RouterId $global:PLR01UplinkAddress -EnableEcmp -confirm:$false | out-null

		#Remove the dopey area 51 NSSA - just to show example of complete OSPF configuration including area creation.
		Get-NsxEdge $global:PLR1Name | Get-NsxEdgerouting | Get-NsxEdgeOspfArea -AreaId 51 | Remove-NsxEdgeOspfArea -confirm:$false

		#Create new Area for OSPF
		Get-NsxEdge $global:PLR1Name | Get-NsxEdgerouting | New-NsxEdgeOspfArea -AreaId $global:TransitOspfAreaId -Type normal -confirm:$false | out-null
		
		#Area to interface mapping
		Get-NsxEdge $global:PLR1Name | Get-NsxEdgerouting | New-NsxEdgeOspfInterface -AreaId $global:TransitOspfAreaId -vNic 1 -confirm:$false | out-null

		#$Edge2 = Get-NsxEdge $global:PLR2Name
		write-host -foregroundcolor Green "Configuring $global:PLR2Name OSPF"
		
		Get-NsxEdge $global:PLR2Name | Get-NsxEdgerouting | set-NsxEdgeRouting -EnableOspf -RouterId $global:PLR02UplinkAddress -EnableEcmp -confirm:$false | out-null

		#Remove the dopey area 51 NSSA - just to show example of complete OSPF configuration including area creation.
		Get-NsxEdge $global:PLR2Name | Get-NsxEdgerouting | Get-NsxEdgeOspfArea -AreaId 51 | Remove-NsxEdgeOspfArea -confirm:$false

		#Create new Area 10 for OSPF
		Get-NsxEdge $global:PLR2Name | Get-NsxEdgerouting | New-NsxEdgeOspfArea -AreaId $global:TransitOspfAreaId -Type normal -confirm:$false | out-null
		
		#Area to interface mapping
		Get-NsxEdge $global:PLR2Name | Get-NsxEdgerouting | New-NsxEdgeOspfInterface -AreaId $global:TransitOspfAreaId -vNic 1 -confirm:$false | out-null
		
		write-host -foregroundcolor Green "Configuring DLR OSPF"
		Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting | set-NsxLogicalRouterRouting -EnableOspf -EnableOspfRouteRedistribution -RouterId $global:DLRUplinkAddress -ProtocolAddress $global:DLR01ProtocolAddress -ForwardingAddress $global:DLRUplinkAddress -confirm:$false | out-null

		#Remove the dopey area 51 NSSA - just to show example of complete OSPF configuration including area creation.
		Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfArea -AreaId 51 | Remove-NsxLogicalRouterOspfArea -confirm:$false

		#Create new Area
		Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfArea -AreaId $global:TransitOspfAreaId -Type normal -confirm:$false | out-null

		#Area to interface mapping
		$LdrTransitInt = get-nsxlogicalrouter | get-nsxlogicalrouterinterface | ? { $_.name -eq $global:TransitLsName}
		Get-NsxLogicalRouter $global:DLRName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfInterface -AreaId $global:TransitOspfAreaId -vNic $LdrTransitInt.index -confirm:$false | out-null
	

		
	}
    write-host -foregroundcolor Green "`nNSX Infrastructure Config Complete`n" 
 		
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
			DeployNSXManager
				if($global:NSXManagerDeployed){
					ConfigureNSXManager
				}
			Disconnect-VIServer $viConnection -Confirm:$false
		}
        1 {"Deployment is cancelled"
			Disconnect-VIServer $viConnection -Confirm:$false
		}
    }

