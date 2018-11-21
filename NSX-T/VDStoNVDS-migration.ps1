$VCConn = Connect-VIServer -Server vcsa-01a.corp.local -user administrator@vsphere.local -password VMware1!

$vm = Get-VM -name "TestVM02"

$networkAdapter = Get-NetworkAdapter -VM $vm 

$destination = Get-VMHost -name esx-05a.corp.local
$destinationPortGroup = Get-VDPortgroup -VDSwitch VDS-Test -Name DummyPG

Move-VM -VM $vm -Destination $destination -NetworkAdapter $networkAdapter -PortGroup $destinationPortGroup

$lstest = Get-View -ViewType OpaqueNetwork | ? {$_.name -eq "LS-Test"}
$null = $vm | Get-NetworkAdapter -name  "Network adapter 1" | Set-NetworkAdapter -NetworkName $lstest.Name -confirm:$false


Disconnect-VIServer -confirm:$false
