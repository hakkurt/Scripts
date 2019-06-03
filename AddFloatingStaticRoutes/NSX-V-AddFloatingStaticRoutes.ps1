<# 
    NSX Create Floating Static Routes on existing Environment
	Created by Hakan Akkurt
	https://www.linkedin.com/in/hakkurt/
	Jun 2019
    	
	Script Functionalities
	
	- Get DLR/UDLR Networks and create static routes on ESGs
	
#>

$ScriptVersion = "1.0"

# NSX Configuration
$NSXHostname = "nsxmanager.demo.local"

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


	Write-Host -ForegroundColor magenta "Starting NSX Static Route Script version $ScriptVersion"

	# Check PowerCli and PowerNSX modules
	
	<# My-Logger "Checking PowerCli and PowerNSX Modules ..." "Yellow"
	
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
	
	My-Logger "PowerCli and PowerNSX Modules check completed..." "green" #>
	
	$NSXUIPassword = Read-Host -Prompt 'Please enter NSX Manager password' -AsSecureString
	$NSXUIPassword=[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($NSXUIPassword))
		
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
			
		
		### UDLR ###
	
		$Ldr = Get-NsxLogicalRouter -Name "UDLR01" -ErrorAction silentlycontinue
		
		$interfaces=$Ldr|Get-NsxLogicalRouterInterface 
		
			foreach ($int in $Interfaces)  {
				
				if($int.type -eq  "uplink")
				{
					$DLRForwardingIPAddress = $int.addressGroups.addressGroup.primaryAddress					
				}
				
				if($int.type -eq  "internal")
				{
				
					$DLRLIFIP = $int.addressGroups.addressGroup.primaryAddress
					$Subnet = $int.addressGroups.addressGroup.subnetPrefixLength
					
						if($Subnet -eq "24") {
							$subnetMask = "255.255.255.0"
							$CIDR="24"
						}
						
						if($Subnet -eq "25") {
							$subnetMask = "255.255.255.128"
							$CIDR="25"
						}
						
						if($Subnet -eq "26") {
							$subnetMask = "255.255.255.192"
							$CIDR="26"
						}
						
						if($Subnet -eq "27") {
							$subnetMask = "255.255.255.224"
							$CIDR="27"
						}
						
						if($Subnet -eq "28") {
							$subnetMask = "255.255.255.240"
							$CIDR="28"
						}
						
						if($Subnet -eq "29") {
							$subnetMask = "255.255.255.248"
							$CIDR="29"
						}
						
					$DLRLIFSubnet=[IPAddress] (([IPAddress] $DLRLIFIP).Address -band ([IPAddress] $subnetMask).Address)
						
					$DLRStaticRoute = $DLRLIFSubnet.IPAddressToString +"/"+$CIDR
						
					
					Get-NsxEdge "EDGE-01" | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network $DLRStaticRoute -NextHop $DLRForwardingIPAddress -AdminDistance 240 -confirm:$false | out-null
					Get-NsxEdge "EDGE-02" | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network $DLRStaticRoute -NextHop $DLRForwardingIPAddress -AdminDistance 240 -confirm:$false | out-null
					
				}	
			}
			
			
		My-Logger "--- Configuration is completed --- " "Blue"
		My-Logger "----------------------------------------------------- " "Green"
	  	
 Disconnect-NsxServer