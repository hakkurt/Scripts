# List all PoweredOn VM list via esxcli

	$VIServer = "vcsa01"
	$VIUsername = "admin"
	$VIPassword = "Test"
	$VMName = "VM1"
	
	$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue

	$esxihosts = Get-VMHost 
		
		foreach($esxihost in $esxihosts) {
			$esxcli = Get-EsxCli -VMhost $esxihost -V2
		
			#$esxcli.vm.process.list() | Where { $_.DisplayName -eq $VMName}
			$vmlist=$esxcli.vm.process.list.Invoke() 
			if($vmlist.DisplayName -eq $VMName) {
				Write-Host "VM found in " $esxihost
			}
		}		

Disconnect-VIServer $viConnection -Confirm:$false