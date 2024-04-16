Param(
    [Hashtable]$parameters = @{
        "type"                 = "CD"; # Type of delivery (CD or Release)
        "apps"                 = $null; # Path to folder containing apps to deploy
        "EnvironmentType"      = "SaaS"; # Environment type
        "EnvironmentName"      = $null; # Environment name
        "Branches"             = $null; # Branches which should deploy to this environment (from settings)
        "AuthContext"          = '{}'; # AuthContext in a compressed Json structure
        "BranchesFromPolicy"   = $null; # Branches which should deploy to this environment (from GitHub environments)
        "Projects"             = "."; # Projects to deploy to this environment
        "ContinuousDeployment" = $false; # Is this environment setup for continuous deployment?
        "runs-on"              = "windows-latest"; # GitHub runner to be used to run the deployment script
    }
)

$ErrorActionPreference = "Stop"
$parameters | ConvertTo-Json -Depth 99 | Out-Host

$tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempPath | Out-Null

Copy-AppFilesToFolder -appFiles $parameters.apps -folder $tempPath | Out-Null
$appsList = @(Get-ChildItem -Path $tempPath -Filter *.app)
if (-not $appsList -or $appsList.Count -eq 0) {
    Write-Host "::error::No apps to publish found."
    exit 1
}

if ($appsList.Count -gt 1) {
    $appsList = Sort-AppFilesByDependencies -appFiles $appsList
    $appsList = $appsList | ForEach-Object { [System.IO.FileInfo]$_ }
    Write-Host "Publishing a total of $($appsList.Count) app(s):"
    $appsList | ForEach-Object { Write-Host "- $($_.Name)" }
}
else {
    Write-Host "Publishing $($appsList[0].Name)"
}

# Download the deployment script
Write-Host "`nDownloading the deployment script"

$url = "https://raw.githubusercontent.com/CBS-BC-AT-Internal/INT.utilities/v0.2.0/powershell/Install-NAVApp.ps1"
$deployScriptPath = Join-Path -Path $tempPath -ChildPath "Deploy-ToBC.ps1"

Write-Host "URL: $url"
Invoke-WebRequest -Uri $url -OutFile $deployScriptPath
Write-Host "Downloaded the deployment script to $deployScriptPath"

foreach ($app in $appsList) {
    Write-Host "`nDeploying app '$($app.Name)'"
    $srvInst = $parameters.EnvironmentName

    # Deploy the app using the downloaded script
    try {
        Invoke-Expression -Command "& '$deployScriptPath' -srvInst '$srvInst' -appPath '$appPath'"
    }
    catch {
        Write-Error "$_"
        exit 1
    }
}

Write-Host "`nSuccessfully deployed all apps to $($parameters.EnvironmentName)"

# Cleanup
Remove-Item -Path $tempPath -Recurse -Force | Out-Null
Write-Host "Removed temporary files."
