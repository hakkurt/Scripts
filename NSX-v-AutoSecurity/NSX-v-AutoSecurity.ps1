# Author: Hakan Akkurt
$ScriptVersion = "1.3"
$NSXHostname = "nsxmgr-01a.corp.local"
$NSXUIPassword = "VMware1!"
$WebStName = "ST-Web"
$AppStName = "ST-App"
$DbStName = "ST-Db"
$SGPrefix = "SG"
$SGSeperator ="-"
$InternalNWAbbr ="INT"
$ExternalNWAbbr ="EXT"
$InternalNWLS ="LS-Internal"
$ExternalNWLS ="LS-External"
$WebAbbr = "Web"
$AppAbbr = "App"
$DbAbbr = "Db"
$Customers ="Customer1","Customer2","Customer3","Customer4","Customer5"


	Write-Host -ForegroundColor Blue "Starting NSX Auto Security Script version $ScriptVersion"

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
		
		
		 $script:DynamicCriteriaKeySubstitute = @{
                "VmName" = "VM.NAME";
                "OsName" = "VM.GUEST_OS_FULL_NAME";
                "ComputerName" = "VM.GUEST_HOST_NAME";
                "SecurityTag" = "VM.SECURITY_TAG"
		}

		# Security Operation
	
		try {
		 
		 Write-Host "   -> Connecting NSX Manager..."
		 
			if(!(Connect-NSXServer -Server $NSXHostname -Username admin -Password $NSXUIPassword -DisableVIAutoConnect -WarningAction SilentlyContinue)) {
				Write-Host -ForegroundColor Red "Unable to connect to NSX Manager, please check the deployment"
				exit
			} else {
				Write-Host "Successfully logged into NSX Manager $NSXHostname..."
			}
				}
		
		catch {
			Throw  "NSX Manager Connection Error"
		}  
	
	
			# Check and Create Security Tags
			
			write-host -foregroundcolor "Green" "Creating Security Tags..."
			
			if (get-nsxsecuritytag $WebStName ) {
				write-host -foregroundcolor "Yellow" "$WebStName is already exist..."
				$WebSt = Get-NsxSecurityTag -name $WebStName
			}
			else{
				$WebSt = New-NsxSecurityTag -name $WebStName
			}
			
			if (get-nsxsecuritytag $AppStName ) {
				write-host -foregroundcolor "Yellow" "$AppStName is already exist..."
				$AppSt = Get-NsxSecurityTag -name $AppStName
			}
			else{
				$AppSt = New-NsxSecurityTag -name $AppStName
			}
			
			if (get-nsxsecuritytag $DbStName ) {
				write-host -foregroundcolor "Yellow" "$DbStName is already exist..."
				$DbSt = Get-NsxSecurityTag -name $DbStName
				}			
			else{
				$DbSt = New-NsxSecurityTag -name $DbStName
			}
		
			# Check and Create Security Groups
			
			write-host -foregroundcolor "Green" "Creating $InternalNWAbbr $WebAbbr Security Groups..."
			
			foreach ($CustomerName in $Customers) {
                   
                $SGName = $SGPrefix + $SGSeperator + $CustomerName + $SGSeperator + $InternalNWAbbr + $SGSeperator + $WebAbbr
				
				if (Get-NsxSecurityGroup $SGName ) {
					write-host -foregroundcolor "Yellow" "$SGName is already exist..."
					$SG = Get-NsxSecurityTag -name $SGName
				}
				else
				{
					
					$SG = New-NsxSecurityGroup -name $SGName -description "Security Group for $CustomerName $InternalNWAbbr $WebAbbr "
					
					Write-Host "$SGName is created "
					
					write-host -foregroundcolor "Green" "Adding SG Members..."
			
					$spec1 = New-NsxDynamicCriteriaSpec -key VmName -condition contains -value $CustomerName
					$spec2 = New-NsxDynamicCriteriaSpec -entity (Get-NsxSecurityTag $WebStName)
					$spec3 = New-NsxDynamicCriteriaSpec -entity (Get-NsxLogicalSwitch $InternalNWLS)
					
					
					$SG | Add-NsxDynamicMemberSet -CriteriaOperator ALL -DynamicCriteriaSpec $spec1,$spec2,$spec3					
									
				}
			}
			
			write-host -foregroundcolor "Green" "Creating $ExternalNWAbbr $WebAbbr Security Groups..."
			
			foreach ( $CustomerName in $Customers) {
                   
                $SGName = $SGPrefix + $SGSeperator + $CustomerName + $SGSeperator + $ExternalNWAbbr + $SGSeperator + $WebAbbr
				
				if (Get-NsxSecurityGroup $SGName ) {
					write-host -foregroundcolor "Yellow" "$SGName is already exist..."
					$SG = Get-NsxSecurityTag -name $SGName
				}
				else
				{
					
					$SG = New-NsxSecurityGroup -name $SGName -description "Security Group for $CustomerName $ExternalNWAbbr $WebAbbr "
					
					Write-Host "$SGName is created "
					
					write-host -foregroundcolor "Green" "Adding SG Members..."
			
					$spec1 = New-NsxDynamicCriteriaSpec -key VmName -condition contains -value $CustomerName
					$spec2 = New-NsxDynamicCriteriaSpec -entity (Get-NsxSecurityTag $WebStName)
					$spec3 = New-NsxDynamicCriteriaSpec -entity (Get-NsxLogicalSwitch $ExternalNWLS)
					
					$SG | Add-NsxDynamicMemberSet -CriteriaOperator ALL -DynamicCriteriaSpec $spec1,$spec2,$spec3					
									
				}
			}
			
			write-host -foregroundcolor "Green" "Creating $InternalNWAbbr $AppAbbr Security Groups..."
			
			foreach ( $CustomerName in $Customers) {
                   
                $SGName = $SGPrefix + $SGSeperator + $CustomerName + $SGSeperator + $InternalNWAbbr + $SGSeperator + $AppAbbr
				
				if (Get-NsxSecurityGroup $SGName ) {
					write-host -foregroundcolor "Yellow" "$SGName is already exist..."
					$SG = Get-NsxSecurityTag -name $SGName
				}
				else
				{
					
					$SG = New-NsxSecurityGroup -name $SGName -description "Security Group for $CustomerName $InternalNWAbbr $AppAbbr "
					
					Write-Host "$SGName is created "
					
					write-host -foregroundcolor "Green" "Adding SG Members..."
			
					$spec1 = New-NsxDynamicCriteriaSpec -key VmName -condition contains -value $CustomerName
					$spec2 = New-NsxDynamicCriteriaSpec -entity (Get-NsxSecurityTag $AppStName)
					$spec3 = New-NsxDynamicCriteriaSpec -entity (Get-NsxLogicalSwitch $InternalNWLS)
					
					$SG | Add-NsxDynamicMemberSet -CriteriaOperator ALL -DynamicCriteriaSpec $spec1,$spec2,$spec3				
									
				}
			}
			
			write-host -foregroundcolor "Green" "Creating $ExternalNWAbbr $AppAbbr Security Groups..."
			
			foreach ( $CustomerName in $Customers) {
                   
                $SGName = $SGPrefix + $SGSeperator + $CustomerName + $SGSeperator + $ExternalNWAbbr + $SGSeperator + $AppAbbr
				
				if (Get-NsxSecurityGroup $SGName ) {
					write-host -foregroundcolor "Yellow" "$SGName is already exist..."
					$SG = Get-NsxSecurityTag -name $SGName
				}
				else
				{
					
					$SG = New-NsxSecurityGroup -name $SGName -description "Security Group for $CustomerName $ExternalNWAbbr $AppAbbr "
					
					Write-Host "$SGName is created "
					
					write-host -foregroundcolor "Green" "Adding SG Members..."
			
					$spec1 = New-NsxDynamicCriteriaSpec -key VmName -condition contains -value $CustomerName
					$spec2 = New-NsxDynamicCriteriaSpec -entity (Get-NsxSecurityTag $AppStName)
					$spec3 = New-NsxDynamicCriteriaSpec -entity (Get-NsxLogicalSwitch $ExternalNWLS)
					
					$SG | Add-NsxDynamicMemberSet -CriteriaOperator ALL -DynamicCriteriaSpec $spec1,$spec2,$spec3				
									
				}
			}
				
			write-host -foregroundcolor "Green" "Creating $InternalNWAbbr $DBAbbr Security Groups..."
			
			foreach ( $CustomerName in $Customers) {
                   
                $SGName = $SGPrefix + $SGSeperator + $CustomerName + $SGSeperator + $InternalNWAbbr + $SGSeperator + $DbAbbr
				
				if (Get-NsxSecurityGroup $SGName ) {
					write-host -foregroundcolor "Yellow" "$SGName is already exist..."
					$SG = Get-NsxSecurityTag -name $SGName
				}
				else
				{
					
					$SG = New-NsxSecurityGroup -name $SGName -description "Security Group for $CustomerName $InternalNWAbbr $DbAbbr "
					
					Write-Host "$SGName is created "
					
					write-host -foregroundcolor "Green" "Adding SG Members..."
			
					$spec1 = New-NsxDynamicCriteriaSpec -key VmName -condition contains -value $CustomerName
					$spec2 = New-NsxDynamicCriteriaSpec -entity (Get-NsxSecurityTag $DbStName)
					$spec3 = New-NsxDynamicCriteriaSpec -entity (Get-NsxLogicalSwitch $InternalNWLS)
					
					$SG | Add-NsxDynamicMemberSet -CriteriaOperator ALL -DynamicCriteriaSpec $spec1,$spec2,$spec3				
									
				}
			}
			
			write-host -foregroundcolor "Green" "Creating $ExternalNWAbbr $DbAbbr Security Groups..."
			
			foreach ( $CustomerName in $Customers) {
                   
                $SGName = $SGPrefix + $SGSeperator + $CustomerName + $SGSeperator + $ExternalNWAbbr + $SGSeperator + $DbAbbr
				
				if (Get-NsxSecurityGroup $SGName ) {
					write-host -foregroundcolor "Yellow" "$SGName is already exist..."
					$SG = Get-NsxSecurityTag -name $SGName
				}
				else
				{
					
					$SG = New-NsxSecurityGroup -name $SGName -description "Security Group for $CustomerName $ExternalNWAbbr $DbAbbr "
					
					Write-Host "$SGName is created "
					
					write-host -foregroundcolor "Green" "Adding SG Members..."
			
					$spec1 = New-NsxDynamicCriteriaSpec -key VmName -condition contains -value $CustomerName
					$spec2 = New-NsxDynamicCriteriaSpec -entity (Get-NsxSecurityTag $DbStName)
					$spec3 = New-NsxDynamicCriteriaSpec -entity (Get-NsxLogicalSwitch $ExternalNWLS)
					
					$SG | Add-NsxDynamicMemberSet -CriteriaOperator ALL -DynamicCriteriaSpec $spec1,$spec2,$spec3				
									
				}
			}
	
	# Remove all Security Groups - For testing - DO not use in Production Environments !!!
	# Get-NsxSecurityGroup  | Remove-NsxSecurityGroup  -confirm:$false	
	
	Disconnect-NsxServer