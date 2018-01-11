<# 
    Create Bulk Logical Switch script
    Created by Hakan Akkurt
    Jan 2018
    version 1.0
#>


$verboseLogFile = "NSX-LS-Creation.log"
$LSListFile="C:\Scripts\LS-List.csv"

# NSX Parameters

$NSXURI = "https://dt-odc3-nsx01.onat.local"
$NSXUsername ="admin"
$NSXUIPassword = "VMware1!"
$TransportZone="TZGlobal"

Function My-Logger {
    param(
    [Parameter(Mandatory=$true)]
    [String]$message
    )

    $timeStamp = Get-Date -Format "dd-MM-yyyy_hh:mm:ss"

    Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
    Write-Host -ForegroundColor Green " $message"
    $logMessage = "[$timeStamp] $message"
    $logMessage | Out-File -Append -LiteralPath $verboseLogFile
}

function Ignore-SelfSignedCerts
{
    try
    {

        Write-Host "Adding TrustAllCertsPolicy type." -ForegroundColor White
        Add-Type -TypeDefinition  @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy
        {
             public bool CheckValidationResult(
             ServicePoint srvPoint, X509Certificate certificate,
             WebRequest request, int certificateProblem)
             {
                 return true;
            }
        }
"@

        Write-Host "TrustAllCertsPolicy type added." -ForegroundColor White
      }
    catch
    {
        Write-Host $_ -ForegroundColor "Yellow"
    }

    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}



$StartTime = Get-Date
	
	if(!(Test-Path $LSListFile)) {
		Write-Host -ForegroundColor Red "`nUnable to find $LSListFile ...`nexiting"
		exit
	}
	
	$auth = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($NSXUsername + ":" + $NSXUIPassword))
	$head = @{"Authorization"="Basic $auth"}
	Ignore-SelfSignedCerts
	
	$r=Invoke-WebRequest -Uri "$NSXURI/api/2.0/vdn/scopes" -Method:Get -headers $head -ContentType "application/xml" -ErrorAction:Stop -TimeoutSec 180
	
	$TZNames= ([xml]$r.Content).vdnScopes.vdnScope.Name
		
	$i=0
	
	foreach($TZName in $TZNames){
	
		if ($TZName -eq $TransportZone){
	
			$vdnscope =([xml]$r.Content).vdnScopes.vdnScope.objectId[$i]
		}
		
		$i=$i+1
		
	}
	
	# Write-Host $vdnscope
		
	$csv=Import-Csv $LSListFile
			   
		foreach($cell in $csv){
			$LSName= $cell.LSName
			My-Logger  "Creating  $LSName .."
		
			$xmlbody = 	"<virtualWireCreateSpec>
					<name>$LSName</name>
					<tenantId>virtual wire tenant</tenantId>
					</virtualWireCreateSpec>"

			$r=Invoke-WebRequest -Uri "$NSXURI/api/2.0/vdn/scopes/$vdnscope/virtualwires" -Body $xmlbody -Method:Post -headers $head -ContentType "application/xml" -ErrorAction:Stop -TimeoutSec 180
			
		}
			
			
	$EndTime = Get-Date
	$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)

	My-Logger  "Duration: $duration minutes" 
