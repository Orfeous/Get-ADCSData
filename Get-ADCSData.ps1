<#
.SYNOPSIS
Exports ADCS certificate data to CSV with logging

.DESCRIPTION
Collects certificate information from Active Directory Certificate Services using certutil
#>

param()

# Logging configuration
$logPath = Join-Path $PSScriptRoot "logs";
$dataPath = Join-Path $PSScriptRoot "data";
$logFile = Join-Path $logPath "$(Get-Date -Format 'yyyy-MM-dd_HH-mm').log";

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss";
    $logEntry = "[$timestamp][$Level] $Message";
    Write-Host $logEntry;
    $logEntry | Out-File -FilePath $logFile -Append -Encoding UTF8;
};

try {
    # Create directories if missing
    if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath -Force | Out-Null };
    if (-not (Test-Path $dataPath)) { New-Item -ItemType Directory -Path $dataPath -Force | Out-Null };

    # Verify ADCS role is installed
    if (-not (Get-WindowsFeature ADCS-Cert-Authority | Where-Object Installed)) {
        Write-Log "ADCS role not installed" "ERROR";
        exit 1;
    };

    Write-Log "Starting certificate data collection";
    
    # Get certificate data
    $certData = certutil -view -restrict "Disposition=20" -out "RequestID,Request.RequesterName,OrgUnit,DistinguishedName,SerialNumber,NotBefore,NotAfter,Request.SubmittedWhen,CommonName,EMail,Request.EMail" csv | ConvertFrom-Csv;
    
    $certObjects = @();

    foreach ($row in $certData) {
        $requestId = $row."Issued Request ID";

        # Dump full cert info for current RequestID
        $certDetails = certutil -view -restrict "RequestID=$requestId" -v csv 2>$null;
        $sanList = @();

        # Extract all AltName[...] SAN entries
        foreach ($line in $certDetails) {
            if ($line -match '^\s*AltName\[\d+\]\s+CERT_ALT_NAME_\w+:\s+"(.+?)"') {
                $sanList += $Matches[1];
            }
        };

        # Join SANs into a single string, separated by commas
        $sanString = $sanList -join ", ";
        # Add SANs to current row
        $row | Add-Member -NotePropertyName SANs -NotePropertyValue $sanString;

        # Store result
        $certObjects += $row;
    };

    # Export to CSV
    $csvPath = Join-Path $dataPath "certdata_$(Get-Date -Format 'yyyy-MM-dd_HH-mm').csv";
    $certObjects | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8;
    Write-Log "Exported $($certObjects.Count) certificates to $csvPath";

}
catch {
    Write-Log "Error occurred: $_" "ERROR";
    exit 2;
};
