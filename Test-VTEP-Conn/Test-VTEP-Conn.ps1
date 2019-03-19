
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
				
					if($VMKernel.PortGroupName -like  "*vxw-*")	{
						
						$esxcli = Get-ESXCLI -vmhost $sourcehost -V2 

						$arguments = $esxcli.network.diag.ping.CreateArgs()
						$arguments.host = $VMKernel.IP
						$arguments.count = 3
						$arguments.netstack = "vxlan"
						$arguments.df = $true
						$arguments.interface = "vmk3"
						$arguments.size = "1600"
						$pingStatus = $esxcli.network.diag.ping.Invoke($arguments)
						
						$VMKernelName=$VMKernel.Name
						$VMKernelIP=$VMKernel.IP
						$PacketLost=$pingStatus.summary.PacketLost
					
						$OutPut= $Cluster.Name + "-" + $VMHost.Name + "-" + $VMKernelName + "-" + $VMKernelIP + "-" + $PacketLost 
						Write-Host $OutPut
						$OutPut | out-file -append output.txt
					}
				

				}
		}
	}

Disconnect-VIServer -Server $Server -Confirm:$false
