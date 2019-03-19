
$vcenter= "vCenter"
$user = "administrator@vsphere.local"
$pass = "pass"
$sourcehost = "esx1"

$Server=Connect-VIServer -Server $vcenter -User $user -Password $pass -WarningAction SilentlyContinue

$Clusters = Get-Cluster | Sort Name

write-host -ForegroundColor green "Cluster	-	Host	-	VMKernel	-	VMKernel IP	-	Packet Loss"

	ForEach ($Cluster in $Clusters){

	$VmHosts = $Cluster | Get-VmHost | Where {$_.ConnectionState -eq "Connected"} | Sort Name

		ForEach ($VmHost in $VmHosts){

			$VMKernels = Get-VMHostNetworkAdapter -VMHost $VmHost -VMKernel
			
				ForEach ($VmKernel in $VMKernels){
				
					if(!$VMKernel.VMotionEnabled)  {     
						if(!$VMKernel.ManagementTrafficEnabled)		{			
						
						$esxcli = Get-ESXCLI -vmhost $sourcehost -V2 

						$arguments = $esxcli.network.diag.ping.CreateArgs()
						$arguments.host = $VMKernel.IP
						$arguments.count = 3
						$arguments.netstack = "vxlan"
						$arguments.df = $true
						$arguments.interface = "vmk3"
						$arguments.size = "1600"
						$pingStatus = $esxcli.network.diag.ping.Invoke($arguments)
						write-host $Cluster "-" $VMHost "-" $VMKernel.Name "-" $VMKernel.IP "-" $pingStatus.summary.PacketLost
						
						}
					} 

				}
		}
	}

Disconnect-VIServer -Server $Server -Confirm:$false
