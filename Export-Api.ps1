# Script CBH-1
<#
.SYNOPSIS
    Export API from Softwareg AG's webMethods.io API
.DESCRIPTION
    Export specific API from Software AG webMethods.io API Cloud and unpack
    files to current directory. This is useful for storing API settings in
    a Version Control System (VCS) as part of CI/CD.
.NOTES
    File Name  : Export-Api.ps1
.LINK
    https://github.com/SoftwareAG/webmethods-io-api-scripts
.PARAMETER CreateConfigFile
    Stored all values (except password) for API export in a hidden configuration
    file in the current directory. Default filename is ".sag-cloud-api".
.PARAMETER ConfigFileName
    Use this name for the configuration file instead of the default (".sag-cloud-api").
    Will be used for creating the configuration file as well as reading from it.
.PARAMETER BaseUrl
    Name of the cloud base URL (default: )
.PARAMETER Tenant 
    Name of the cloud tenant.
.PARAMETER Username 
    Username for connecting to tenant
.PARAMETER Password
    Password for connecting to tenant
.PARAMETER ApiName
    Name of API to export
.PARAMETER ApiVersion
    Version of API to export
.EXAMPLE
    Export-Api -Tenant foobar -Username user1 -Password secret -CreateConfigFile -ApiName TestAPI -ApiVersion "1.0"
    
    Will store the provided values (except password, which needs to be set by the script
    Set-Password.ps1) in default configuration file and then perform the export of the 
    specified API and version
.EXAMPLE
    Export-Api

    Performs API export based on contents of configuration files found in current directory
#>


Param (
    [string]$Tenant,
    [string]$Username,
    [string]$Password,
    [string]$ApiName,
    [string]$ApiVersion,
    [string]$ConfigFileName = ".sag-cloud-api",
    [switch]$Verbose,
    [switch]$CreateConfigFile,
    [string]$BaseUrl = "https://$Tenant.gateway.webmethodscloud.com/rest/apigateway"
)

Set-StrictMode -Version 1.0

# Property keys for configuration file
[string]$cfgFileKeyBaseUrl='baseUrl'
[string]$cfgFileKeyUser='user'
[string]$cfgFileKeyPassword='password'
[string]$cfgFileKeyApiName='apiName'
[string]$cfgFileKeyApiVersion='apiVersion'

# Read configuration file, if possible
if ((Test-Path $ConfigFileName -PathType Leaf)) {
    $settings = ConvertFrom-Stringdata (Get-Content $ConfigFileName -raw)
    $BaseUrl = $settings."$cfgFileKeyBaseUrl"
    $ApiName = $settings."$cfgFileKeyApiName"
    $ApiVersion = $settings."$cfgFileKeyApiVersion"
    $Username = $settings."$cfgFileKeyUser"
    $pwdFromFile = $settings."$cfgFileKeyPassword" | ConvertTo-SecureString
    $credential = New-Object System.Management.Automation.PSCredential($Username, $pwdFromFile)
} else {

    # If credentials are provided on the command line, use them ...
    if ( ($null -ne $Username) -and ($null -ne $Password) -And ('' -ne $Username) -And ('' -ne $Password)) {
        $pwdFromCmdline = ConvertTo-SecureString $Password -Force -AsPlainText
        $credential = New-Object System.Management.Automation.PSCredential($Username, $pwdFromCmdline)
    } else {
        # ... otherwise prompt for username and password
        $credential = Get-Credential
    }
}


if ($PSBoundParameters['Verbose']) {
    Write-Output "Tenant        : $Tenant"
    Write-Output "User          : $Username"
    Write-Output "API name      : $ApiName"
    Write-Output "API version   : $ApiVersion"
}


# Create .gitignore file, if it does not exist
[string]$ConfigFileileNameGitIgnore = '.gitignore'
if (!(Test-Path $ConfigFileileNameGitIgnore -PathType Leaf)) {
    Set-Content -Path .\$ConfigFileileNameGitIgnore -Value "$settingsFilePwdPrefix*`n$settingsFileApi`nExportReport.json"
}


# Create config file, if requested
if ($PSBoundParameters['CreateConfigFile']) {
    if(!(Test-Path $ConfigFileName)) {
        [string]$pwdForConfigFile = $credential.Password | ConvertFrom-SecureString
        Set-Content -Path .\$ConfigFileName -Value "$cfgFileKeyBaseUrl=$BaseUrl`n$cfgFileKeyUser=$Username`n$cfgFileKeyPassword=$pwdForConfigFile`n$cfgFileKeyApiName=$ApiName`n$cfgFileKeyApiVersion=$ApiVersion"
    } else {
        Write-Output "Config file already exists in current directory, nothing done"
    }
}

# Retrieve API ID by API name and version
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Accept", 'application/json')
$body = "{  `"types`": [`"API`"],  `"scope`": [{ `"attributeName`": `"apiName`", `"keyword`": `"$ApiName`" },{`"attributeName`": `"apiVersion`",`"keyword`": `"$ApiVersion`"}],`"condition`": `"and`"}"

if ($PSBoundParameters['Verbose']) {
    Write-Output "Search details: $body"
}

$searchIdResultWeb = Invoke-WebRequest "$BaseUrl/search" -Method Post -Body $body -Headers $headers -ContentType "application/json" -Credential $credential -ErrorVariable restError
$searchIdResultJson = $searchIdResultWeb.Content | ConvertFrom-Json 
$searchIdResult = $searchIdResultJson.api
[string]$apiId = $searchIdResult.id

if ($PSBoundParameters['Verbose']) {
    Write-Output "Search result:"
    Write-Output ($searchIdResultJson | ConvertTo-Json)
}

# Check if API was found
if (($null -eq $apiId) -or ('' -eq $apiId)) {
    Write-Output "No API found for name `"$ApiName`" and version `"$apiVersion`" on tenant `"$Tenant`""
    exit 1
}

Write-Output "$apiId"

# Trigger export
[string]$tempFile='api.zip'
$headersDownload = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headersDownload.Add("Accept", 'multipart/form-data')
[string]$exportUri = "$BaseUrl/archive?include-applications=false&policies=*&apis=$apiId"

if ($PSBoundParameters['Verbose']) {
    Write-Output "Export URI:  $exportUri"
}

Invoke-RestMethod -Uri $exportUri  -Method Get -Headers $headersDownload -ContentType "application/json" -Credential $credential -OutFile $tempFile
if (Test-Path $tempFile) {
    Expand-Archive .\$tempFile . -Force
    Remove-Item $tempFile
} else {
    Write-Error "No export file $tempFile found"
}
