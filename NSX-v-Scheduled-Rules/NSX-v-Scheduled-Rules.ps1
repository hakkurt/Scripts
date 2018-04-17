<# 
    NSX Disable or Remove Expired Rule
	Created by Hakan Akkurt
	https://www.linkedin.com/in/hakkurt/
	April 2018
    
	Check DFW Rule Comments field for a date (dd/MM/yyyy format)
	If written date is older then today, rule will be disabled
	
#>

$ScriptVersion = "1.0"
$Operation = "disable" # Select disable or remove


# Deployment Parameters
$verboseLogFile = "ScriptLogs.log"

# NSX Configuration
$NSXHostname = "dt-odc4-nsx01.onat.local"
$NSXUIPassword = "VMware1!"

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
 _____  ________          __   _____ _                              
|  __ \|  ____\ \        / /  / ____| |                             
| |  | | |__   \ \  /\  / /  | |    | | ___  __ _ _ __  _   _ _ __  
| |  | |  __|   \ \/  \/ /   | |    | |/ _ \/ _` | '_ \| | | | '_ \ 
| |__| | |       \  /\  /    | |____| |  __/ (_| | | | | |_| | |_) |
|_____/|_|        \/  \/      \_____|_|\___|\__,_|_| |_|\__,_| .__/ 
                                                             | |    
                                                             |_|    
"@

Write-Host -ForegroundColor magenta $banner 

	Write-Host -ForegroundColor magenta "Starting NSX Rule Cleanup Script"

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
	
	$today = Get-Date -Format "dd/MM/yyyy"
	
		foreach ( $section in (Get-NsxFirewallSection)) {
			$req = Invoke-NsxWebRequest -URI "/api/4.0/firewall/globalroot-0/config/layer3sections/$($section.id)" -method get
			$content = [xml]$req.Content
				
				foreach ($rule in $content.section.rule) { 
				
					if(($today -gt $rule.notes) -and ($rule.notes -ne $null)){
						
						$rule.disabled = "true"
						$ruleid=$rule.id
						$rulename=$rule.name
						#$rule.notes = "Disabled by script"
						My-Logger "Rule id : $ruleid - Rule Name: $rulename is disabled"
					
					}
				
				}
				
			$AdditionalHeaders = @{"If-Match"=$req.Headers.ETag}
			$response = Invoke-NsxWebRequest -URI "/api/4.0/firewall/globalroot-0/config/layer3sections/$($section.id)" -method put -extraheader $AdditionalHeaders -body $content.section.outerxml
				
				if ( -not $response.StatusCode -eq 200 ) {
					My-Logger "Error Occured"
				}
				else {
					My-Logger "Script run successfully"
				}
		}
	
 		
	Disconnect-NsxServer