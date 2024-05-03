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

function New-TemporaryFolder {
    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
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
        Write-Host "Publishing a total of $($appsList.Count) app(s):"
        $appsList | ForEach-Object { Write-Host "- $($_.Name)" }
    }
    else {
        Write-Host "Publishing $($appsList[0].Name)"
    }

    return $appsList
}

function Get-PublishScript {
    param (
        [string]$url = "https://raw.githubusercontent.com/CBS-BC-AT-Internal/INT.utilities/v0.2.0/powershell/Install-NAVApp.ps1",
        [string]$outputPath
    )
    Write-Host "`nDownloading the deployment script"
    Write-Host "URL: $url"
    $deployScriptPath = Join-Path -Path $outputPath -ChildPath "Deploy-ToBC.ps1"
    Invoke-WebRequest -Uri $url -OutFile $deployScriptPath
    Write-Host "Downloaded the deployment script to $deployScriptPath"

    return $deployScriptPath
}

function Deploy-App {
    param (
        [string]$srvInst,
        [System.IO.FileInfo]$app
    )
    $appPath = $app.FullName
    Write-Host "`nDeploying app '$($app.Name)'"
    Write-Host "::debug::ScriptPath: $deployScriptPath"
    Write-Host "::debug::srvInst: $srvInst"
    Write-Host "::debug::app: $appPath"

    # Deploy the app using the downloaded script
    Invoke-Expression -Command "& '$deployScriptPath' -srvInst '$srvInst' -appPath '$appPath'"
}

function Remove-TempFiles {
    param (
        [string]$tempPath
    )
    Remove-Item -Path $outputPath -Recurse -Force | Out-Null
    Write-Host "Removed temporary files."
}

$ErrorActionPreference = "Stop"
$parameters | ConvertTo-Json -Depth 99 | Out-Host
$tempPath = New-TemporaryFolder
Copy-AppFilesToFolder -appFiles $parameters.apps -folder $tempPath | Out-Null
$appsList = Get-AppList -outputPath $tempPath
$deployScriptPath = Get-PublishScript -outputPath $tempPath

foreach ($app in $appsList) {
    Deploy-App -srvInst $parameters.EnvironmentName -app $app
}

Write-Host "`nSuccessfully deployed all apps to $($parameters.EnvironmentName)"
Remove-TempFiles -tempPath $tempPath
