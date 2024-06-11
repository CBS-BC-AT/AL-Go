Param(
    [Hashtable]$parameters = @{
        [string] "type"               = "CD"; # Type of delivery (CD or Release)
        "apps"                        = $null; # Path to folder containing apps to deploy
        [string] "EnvironmentType"    = "SaaS"; # Environment type
        "EnvironmentName"             = $null; # Environment name
        "Branches"                    = $null; # Branches which should deploy to this environment (from settings)
        [string] "AuthContext"        = '{}'; # AuthContext in a compressed Json structure
        "BranchesFromPolicy"          = $null; # Branches which should deploy to this environment (from GitHub environments)
        "Projects"                    = "."; # Projects to deploy to this environment
        [bool] "ContinuousDeployment" = $false; # Is this environment setup for continuous deployment?
        [string] "runs-on"            = "windows-latest"; # GitHub runner to be used to run the deployment script
        [string] "SyncMode"           = "Add"; # Sync mode for the deployment. (Add or ForceSync)
    }
)

function New-TemporaryFolder {
    $tempPath = Join-Path -Path $PWD -ChildPath "_temp"
    New-Item -ItemType Directory -Path $tempPath | Out-Null

    return $tempPath
}

function Get-AppList {
    param (
        [string]$outputPath
    )
    $appsList = @(Get-ChildItem -Path $outputPath -Filter *.app)
    if (-not $appsList -or $appsList.Count -eq 0) {
        Write-Host "::error::No apps to publish found."
        exit 1
    }

    if ($appsList.Count -gt 1) {
        $appsList = Sort-AppFilesByDependencies -appFiles $appsList
        $appsList = $appsList | ForEach-Object { [System.IO.FileInfo]$_ }
        Write-Host "Publishing a total of ${appsList.Count} app(s):"
        $appsList | ForEach-Object { Write-Host "- $($_.Name)" }
    }
    else {
        Write-Host "Publishing $($appsList[0].Name)."
    }

    return $appsList
}

function Get-PublishScript {
    param (
        [string]$url = "https://raw.githubusercontent.com/CBS-BC-AT-Internal/INT.utilities/v0.2.11/powershell/Update-NAVApp.ps1",
        [Parameter(Mandatory = $true)]
        [string]$outputPath
    )
    Write-Host "`nDownloading the deployment script..."
    Write-Host "URL: $url"
    if (-not (Test-Path -Path $outputPath)) {
        throw "Output path '$outputPath' does not exist."
    }
    $filename = [System.IO.Path]::GetFileName($url)
    $deployScriptPath = Join-Path -Path $outputPath -ChildPath $filename
    Invoke-WebRequest -Uri $url -OutFile $deployScriptPath
    Write-Host "Downloaded the deployment script to $deployScriptPath"

    return $deployScriptPath
}

function Deploy-App {
    param (
        [Parameter(Mandatory = $true)]
        [string]$srvInst,
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$app,
        [Parameter(Mandatory = $true)]
        [string]$deployScriptPath,
        [string]$bcVersion,
        [string]$modulePath,
        [bool]$forceSync
    )

    Write-Host "`nDeploying app '$($app.Name)'"
    $params = @{
        "srvInst"   = $srvInst;
        "appPath"   = $app.FullName;
    }
    if ($forceSync) {
        $params["forceSync"] = $true
    }
    if ($bcVersion) {
        $params["bcVersion"] = $bcVersion
    }
    if ($modulePath) {
        $params["modulePath"] = $modulePath
    }

    $commandString = $deployScriptPath
    foreach ($key in $params.Keys) {
        Write-Host "::debug::${key}: $($params[$key])"
        $commandString += " -${key} '$($params[$key])'"
    }

    # Deploy the app using the downloaded script
    Write-Host "$commandString"
    Invoke-Expression -Command $commandString
}

function Remove-TempFiles {
    param (
        [string]$tempPath
    )
    Remove-Item -Path $tempPath -Recurse -Force | Out-Null
    Write-Host "Removed temporary files."
}

$ErrorActionPreference = "Stop"
$parameters | ConvertTo-Json -Depth 99 | Out-Host
$tempPath = New-TemporaryFolder
Copy-AppFilesToFolder -appFiles $parameters.apps -folder $tempPath | Out-Null
$appsList = Get-AppList -outputPath $tempPath
$deployScriptPath = Get-PublishScript -outputPath $tempPath
$forceSync = $parameters.SyncMode -eq "ForceSync"

$authcontext = $parameters.AuthContext | ConvertFrom-Json

try { $bcVersion = $authcontext.BCVersion }
catch { $bcVersion = $null }
try { $modulePath = $authcontext.ModulePath }
catch { $modulePath = $null }

$deployAppParams = @{
    srvInst          = $parameters.EnvironmentName
    deployScriptPath = $deployScriptPath
    bcVersion        = $bcVersion
    modulePath       = $modulePath
    forceSync        = $forceSync
}

foreach ($app in $appsList) {
    $deployAppParams["app"] = $app
    Deploy-App @deployAppParams
}

Write-Host "`nSuccessfully deployed all apps to ${parameters.EnvironmentName}."
Remove-TempFiles -tempPath $tempPath
