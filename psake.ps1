[CmdletBinding()]
param(
    [Parameter(Mandatory=$False)]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert,

    [Parameter(Mandatory=$False)]
    [System.Collections.Hashtable]$TestResources
)

# NOTE: `Set-BuildEnvironment -Force -Path $PSScriptRoot` from build.ps1 makes the following $env: available:
<#
    $env:BHBuildSystem = "Unknown"
    $env:BHProjectPath = "U:\powershell\ProjectRepos\Sudo"
    $env:BHBranchName = "master"
    $env:BHCommitMessage = "!deploy"
    $env:BHBuildNumber = 0
    $env:BHProjectName = "Sudo"
    $env:BHPSModuleManifest = "U:\powershell\ProjectRepos\Sudo\Sudo\Sudo.psd1"
    $env:BHModulePath = "U:\powershell\ProjectRepos\Sudo\Sudo"
    $env:BHBuildOutput = "U:\powershell\ProjectRepos\Sudo\BuildOutput"
#>

# NOTE: If -TestResources was used, the folloqing resources should be available
<#
    $TestResources = @{
        UserName        = $UserName
        SimpleUserName  = $SimpleUserName
        Password        = $Password
        Creds           = $Creds
    }
#>

# PSake makes variables declared here available in other scriptblocks
# Init some things
Properties {
    $PublicScriptFiles = Get-ChildItem "$env:BHModulePath\Public" -File -Filter *.ps1 -Recurse
    $PrivateScriptFiles = Get-ChildItem -Path "$env:BHModulePath\Private" -File -Filter *.ps1 -Recurse

    $Timestamp = Get-Date -UFormat "%Y%m%d-%H%M%S"
    $PSVersion = $PSVersionTable.PSVersion.Major
    $TestFile = "TestResults_PS$PSVersion`_$TimeStamp.xml"
    $lines = '----------------------------------------------------------------------'

    $Verbose = @{}
    if ($ENV:BHCommitMessage -match "!verbose") {
        $Verbose = @{Verbose = $True}
    }

    if ($Cert) {
        # Need to Declare $Cert here in the 'Properties' block so that it's available in other script blocks
        $Cert = $Cert
    }
}

Task Default -Depends Test

Task Init -RequiredVariables  {
    $lines
    Set-Location $ProjectRoot
    "Build System Details:"
    Get-Item ENV:BH*
    "`n"
}

Task Compile -Depends Init {
    $BoilerPlateFunctionSourcing = @'
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

# Get public and private function definition files.
[array]$Public  = Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue
[array]$Private = Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue
$ThisModule = $(Get-Item $PSCommandPath).BaseName

# Dot source the Private functions
foreach ($import in $Private) {
    try {
        . $import.FullName
    }
    catch {
        Write-Error -Message "Failed to import function $($import.FullName): $_"
    }
}

if ($(Test-Path "$PSScriptRoot\module.requirements.psd1")) {
    $ModuleManifestData = Import-PowerShellDataFile "$PSScriptRoot\module.requirements.psd1"
    $ModulesToInstallAndImport = $ModuleManifestData.Keys | Where-Object {$_ -ne "PSDependOptions"}
}

# NOTE: If you're not sure if the Required Module is Locally Available or Externally Available,
# add it the the -NeededExternallyAvailableModules string array
$InvModDepSplatParams = @{
    RequiredModules                     = $ModulesToInstallAndImport
    InstallModulesNotAvailableLocally   = $True
    ErrorAction                         = "SilentlyContinue"
    WarningAction                       = "SilentlyContinue"
}
$ModuleDependenciesMap = InvokeModuleDependencies @InvModDepSplatParams

if ($LoadModuleDependenciesResult.UnacceptableUnloadedModules.Count -gt 0) {
    Write-Warning "The following Modules were not able to be loaded:`n$($LoadModuleDependenciesResult.UnacceptableUnloadedModules.ModuleName -join "`n")"

    if ($PSVersionTable.PSEdition -eq "Core" -and $PSVersionTable.Platform -eq "Win32NT") {

'@ + @"

        Write-Warning "'$env:BHProjectName' will probably not work with PowerShell Core..."

"@ + @'

    }
}

# Public Functions

'@

    ###### BEGIN Unique Additions to this Module ######
    # Add PowerShim Module
    <#
    $PowerShimFileContent = Get-Content "$env:BHModulePath\powershim.psm1"
    $SigBlockLineNumber = $PowerShimFileContent.IndexOf('# SIG # Begin signature block')
    $ContentSansSigBlock = $($($PowerShimFileContent[0..$($SigBlockLineNumber-1)]) -join "`n").Trim() -split "`n"
    $UniqueCode = $ContentSansSigBlock -join "`n"

    if ($UniqueCode) {
        $BoilerPlateFunctionSourcing = $BoilerPlateFunctionSourcing + $UniqueCode
    }
    #>
    ###### END Unique Additions to this Module ######

    Set-Content -Path "$env:BHModulePath\$env:BHProjectName.psm1" -Value $BoilerPlateFunctionSourcing

    [System.Collections.ArrayList]$FunctionTextToAdd = @()
    foreach ($ScriptFileItem in $PublicScriptFiles) {
        $FileContent = Get-Content $ScriptFileItem.FullName
        $SigBlockLineNumber = $FileContent.IndexOf('# SIG # Begin signature block')
        $FunctionSansSigBlock = $($($FileContent[0..$($SigBlockLineNumber-1)]) -join "`n").Trim() -split "`n"
        $null = $FunctionTextToAdd.Add("`n")
        $null = $FunctionTextToAdd.Add($FunctionSansSigBlock)
    }
    $null = $FunctionTextToAdd.Add("`n")

    Add-Content -Value $FunctionTextToAdd -Path "$env:BHModulePath\$env:BHProjectName.psm1"

    # Finally, add array $FunctionsForSBuse in case we want to use this Module Remotely
    $FunctionsForSBUseString = @'
[System.Collections.ArrayList]$FunctionsForSBUse = @(
    ${Function:FixNTVirtualMachinesPerms}.Ast.Extent.Text 
    ${Function:GetDomainController}.Ast.Extent.Text
    ${Function:GetElevation}.Ast.Extent.Text
    ${Function:GetFileLockProcess}.Ast.Extent.Text
    ${Function:GetModMapObject}.Ast.Extent.Text
    ${Function:GetModuleDependencies}.Ast.Extent.Text
    ${Function:GetNativePath}.Ast.Extent.Text
    ${Function:GetVSwitchAllRelatedInfo}.Ast.Extent.Text
    ${Function:GetWinPSInCore}.Ast.Extent.Text
    ${Function:InstallFeatureDism}.Ast.Extent.Text
    ${Function:InstallHyperVFeatures}.Ast.Extent.Text
    ${Function:InvokeModuleDependencies}.Ast.Extent.Text
    ${Function:InvokePSCompatibility}.Ast.Extent.Text
    ${Function:NewUniqueString}.Ast.Extent.Text
    ${Function:PauseForWarning}.Ast.Extent.Text
    ${Function:ResolveHost}.Ast.Extent.Text
    ${Function:TestIsValidIPAddress}.Ast.Extent.Text
    ${Function:UnzipFile}.Ast.Extent.Text
    ${Function:Create-Domain}.Ast.Extent.Text
    ${Function:Create-RootCA}.Ast.Extent.Text
    ${Function:Create-SubordinateCA}.Ast.Extent.Text
    ${Function:Create-TwoTierPKI}.Ast.Extent.Text
    ${Function:Create-TwoTierPKICFSSL}.Ast.Extent.Text
    ${Function:Deploy-HyperVVagrantBoxManually}.Ast.Extent.Text
    ${Function:Generate-Certificate}.Ast.Extent.Text
    ${Function:Get-DSCEncryptionCert}.Ast.Extent.Text
    ${Function:Get-VagrantBoxManualDownload}.Ast.Extent.Text
    ${Function:Manage-HyperVVM}.Ast.Extent.Text
    ${Function:New-DomainController}.Ast.Extent.Text
    ${Function:New-RootCA}.Ast.Extent.Text
    ${Function:New-Runspace}.Ast.Extent.Text
    ${Function:New-SelfSignedCertificateEx}.Ast.Extent.Text
    ${Function:New-SubordinateCA}.Ast.Extent.Text
)
'@

    Add-Content -Value $FunctionsForSBUseString -Path "$env:BHModulePath\$env:BHProjectName.psm1"

    if ($Cert) {
        # At this point the .psm1 is finalized, so let's sign it
        try {
            $SetAuthenticodeResult = Set-AuthenticodeSignature -FilePath "$env:BHModulePath\$env:BHProjectName.psm1" -cert $Cert
            if (!$SetAuthenticodeResult -or $SetAuthenticodeResult.Status -eq "HashMisMatch") {throw}
        }
        catch {
            Write-Error "Failed to sign '$env:BHProjectName.psm1' with Code Signing Certificate! Invoke-Pester will not be able to load '$env:BHProjectName.psm1'! Halting!"
            $global:FunctionResult = "1"
            return
        }
    }
}

Task Test -Depends Compile  {
    $lines
    "`n`tSTATUS: Testing with PowerShell $PSVersion"

    $PesterSplatParams = @{
        PassThru        = $True
        OutputFormat    = "NUnitXml"
        OutputFile      = "$env:BHBuildOutput\$TestFile"
    }
    if ($TestResources) {
        $ScriptParamHT = @{
            Path = "$env:BHProjectPath\Tests"
            Parameters = @{TestResources = $TestResources}
        }
        $PesterSplatParams.Add("Script",$ScriptParamHT)
    }
    else {
        $PesterSplatParams.Add("Path","$env:BHProjectPath\Tests")
    }

    # Gather test results. Store them in a variable and file
    $TestResults = Invoke-Pester @PesterSplatParams

    # In Appveyor?  Upload our tests! #Abstract this into a function?
    if ($env:BHBuildSystem -eq 'AppVeyor') {
        (New-Object 'System.Net.WebClient').UploadFile(
            "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)",
            "$env:BHBuildOutput\$TestFile" )
    }

    Remove-Item "$env:BHBuildOutput\$TestFile" -Force -ErrorAction SilentlyContinue

    # Failed tests?
    # Need to tell psake or it will proceed to the deployment. Danger!
    if ($TestResults.FailedCount -gt 0) {
        Write-Error "Failed '$($TestResults.FailedCount)' tests, build failed"
    }
    "`n"
}

Task Build -Depends Test {
    $lines
    
    # Load the module, read the exported functions, update the psd1 FunctionsToExport
    Set-ModuleFunctions

    # Bump the module version if we didn't already
    Try
    {
        [version]$GalleryVersion = Get-NextNugetPackageVersion -Name $env:BHProjectName -ErrorAction Stop
        #[version]$GalleryVersion = Get-NextPSGalleryVersion -Name $env:BHProjectName -ErrorAction Stop
        [version]$GithubVersion = Get-MetaData -Path $env:BHPSModuleManifest -PropertyName ModuleVersion -ErrorAction Stop
        if($GalleryVersion -ge $GithubVersion) {
            Update-Metadata -Path $env:BHPSModuleManifest -PropertyName ModuleVersion -Value $GalleryVersion -ErrorAction stop
        }
    }
    Catch
    {
        "Failed to update version for '$env:BHProjectName': $_.`nContinuing with existing version"
    }
}

Task Deploy -Depends Build {
    $lines

    $Params = @{
        Path = $PSScriptRoot
        Force = $true
        Recurse = $false
    }
    Invoke-PSDeploy @Verbose @Params
}

# SIG # Begin signature block
# MIIMiAYJKoZIhvcNAQcCoIIMeTCCDHUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUPvGpWaUzU5gGmfvnhMFXA+QD
# F+Sgggn9MIIEJjCCAw6gAwIBAgITawAAAB/Nnq77QGja+wAAAAAAHzANBgkqhkiG
# 9w0BAQsFADAwMQwwCgYDVQQGEwNMQUIxDTALBgNVBAoTBFpFUk8xETAPBgNVBAMT
# CFplcm9EQzAxMB4XDTE3MDkyMDIxMDM1OFoXDTE5MDkyMDIxMTM1OFowPTETMBEG
# CgmSJomT8ixkARkWA0xBQjEUMBIGCgmSJomT8ixkARkWBFpFUk8xEDAOBgNVBAMT
# B1plcm9TQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDCwqv+ROc1
# bpJmKx+8rPUUfT3kPSUYeDxY8GXU2RrWcL5TSZ6AVJsvNpj+7d94OEmPZate7h4d
# gJnhCSyh2/3v0BHBdgPzLcveLpxPiSWpTnqSWlLUW2NMFRRojZRscdA+e+9QotOB
# aZmnLDrlePQe5W7S1CxbVu+W0H5/ukte5h6gsKa0ktNJ6X9nOPiGBMn1LcZV/Ksl
# lUyuTc7KKYydYjbSSv2rQ4qmZCQHqxyNWVub1IiEP7ClqCYqeCdsTtfw4Y3WKxDI
# JaPmWzlHNs0nkEjvnAJhsRdLFbvY5C2KJIenxR0gA79U8Xd6+cZanrBUNbUC8GCN
# wYkYp4A4Jx+9AgMBAAGjggEqMIIBJjASBgkrBgEEAYI3FQEEBQIDAQABMCMGCSsG
# AQQBgjcVAgQWBBQ/0jsn2LS8aZiDw0omqt9+KWpj3DAdBgNVHQ4EFgQUicLX4r2C
# Kn0Zf5NYut8n7bkyhf4wGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwDgYDVR0P
# AQH/BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAUdpW6phL2RQNF
# 7AZBgQV4tgr7OE0wMQYDVR0fBCowKDAmoCSgIoYgaHR0cDovL3BraS9jZXJ0ZGF0
# YS9aZXJvREMwMS5jcmwwPAYIKwYBBQUHAQEEMDAuMCwGCCsGAQUFBzAChiBodHRw
# Oi8vcGtpL2NlcnRkYXRhL1plcm9EQzAxLmNydDANBgkqhkiG9w0BAQsFAAOCAQEA
# tyX7aHk8vUM2WTQKINtrHKJJi29HaxhPaHrNZ0c32H70YZoFFaryM0GMowEaDbj0
# a3ShBuQWfW7bD7Z4DmNc5Q6cp7JeDKSZHwe5JWFGrl7DlSFSab/+a0GQgtG05dXW
# YVQsrwgfTDRXkmpLQxvSxAbxKiGrnuS+kaYmzRVDYWSZHwHFNgxeZ/La9/8FdCir
# MXdJEAGzG+9TwO9JvJSyoGTzu7n93IQp6QteRlaYVemd5/fYqBhtskk1zDiv9edk
# mHHpRWf9Xo94ZPEy7BqmDuixm4LdmmzIcFWqGGMo51hvzz0EaE8K5HuNvNaUB/hq
# MTOIB5145K8bFOoKHO4LkTCCBc8wggS3oAMCAQICE1gAAAH5oOvjAv3166MAAQAA
# AfkwDQYJKoZIhvcNAQELBQAwPTETMBEGCgmSJomT8ixkARkWA0xBQjEUMBIGCgmS
# JomT8ixkARkWBFpFUk8xEDAOBgNVBAMTB1plcm9TQ0EwHhcNMTcwOTIwMjE0MTIy
# WhcNMTkwOTIwMjExMzU4WjBpMQswCQYDVQQGEwJVUzELMAkGA1UECBMCUEExFTAT
# BgNVBAcTDFBoaWxhZGVscGhpYTEVMBMGA1UEChMMRGlNYWdnaW8gSW5jMQswCQYD
# VQQLEwJJVDESMBAGA1UEAxMJWmVyb0NvZGUyMIIBIjANBgkqhkiG9w0BAQEFAAOC
# AQ8AMIIBCgKCAQEAxX0+4yas6xfiaNVVVZJB2aRK+gS3iEMLx8wMF3kLJYLJyR+l
# rcGF/x3gMxcvkKJQouLuChjh2+i7Ra1aO37ch3X3KDMZIoWrSzbbvqdBlwax7Gsm
# BdLH9HZimSMCVgux0IfkClvnOlrc7Wpv1jqgvseRku5YKnNm1JD+91JDp/hBWRxR
# 3Qg2OR667FJd1Q/5FWwAdrzoQbFUuvAyeVl7TNW0n1XUHRgq9+ZYawb+fxl1ruTj
# 3MoktaLVzFKWqeHPKvgUTTnXvEbLh9RzX1eApZfTJmnUjBcl1tCQbSzLYkfJlJO6
# eRUHZwojUK+TkidfklU2SpgvyJm2DhCtssFWiQIDAQABo4ICmjCCApYwDgYDVR0P
# AQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBS5d2bhatXq
# eUDFo9KltQWHthbPKzAfBgNVHSMEGDAWgBSJwtfivYIqfRl/k1i63yftuTKF/jCB
# 6QYDVR0fBIHhMIHeMIHboIHYoIHVhoGubGRhcDovLy9DTj1aZXJvU0NBKDEpLENO
# PVplcm9TQ0EsQ049Q0RQLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNl
# cnZpY2VzLENOPUNvbmZpZ3VyYXRpb24sREM9emVybyxEQz1sYWI/Y2VydGlmaWNh
# dGVSZXZvY2F0aW9uTGlzdD9iYXNlP29iamVjdENsYXNzPWNSTERpc3RyaWJ1dGlv
# blBvaW50hiJodHRwOi8vcGtpL2NlcnRkYXRhL1plcm9TQ0EoMSkuY3JsMIHmBggr
# BgEFBQcBAQSB2TCB1jCBowYIKwYBBQUHMAKGgZZsZGFwOi8vL0NOPVplcm9TQ0Es
# Q049QUlBLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNlcnZpY2VzLENO
# PUNvbmZpZ3VyYXRpb24sREM9emVybyxEQz1sYWI/Y0FDZXJ0aWZpY2F0ZT9iYXNl
# P29iamVjdENsYXNzPWNlcnRpZmljYXRpb25BdXRob3JpdHkwLgYIKwYBBQUHMAKG
# Imh0dHA6Ly9wa2kvY2VydGRhdGEvWmVyb1NDQSgxKS5jcnQwPQYJKwYBBAGCNxUH
# BDAwLgYmKwYBBAGCNxUIg7j0P4Sb8nmD8Y84g7C3MobRzXiBJ6HzzB+P2VUCAWQC
# AQUwGwYJKwYBBAGCNxUKBA4wDDAKBggrBgEFBQcDAzANBgkqhkiG9w0BAQsFAAOC
# AQEAszRRF+YTPhd9UbkJZy/pZQIqTjpXLpbhxWzs1ECTwtIbJPiI4dhAVAjrzkGj
# DyXYWmpnNsyk19qE82AX75G9FLESfHbtesUXnrhbnsov4/D/qmXk/1KD9CE0lQHF
# Lu2DvOsdf2mp2pjdeBgKMRuy4cZ0VCc/myO7uy7dq0CvVdXRsQC6Fqtr7yob9NbE
# OdUYDBAGrt5ZAkw5YeL8H9E3JLGXtE7ir3ksT6Ki1mont2epJfHkO5JkmOI6XVtg
# anuOGbo62885BOiXLu5+H2Fg+8ueTP40zFhfLh3e3Kj6Lm/NdovqqTBAsk04tFW9
# Hp4gWfVc0gTDwok3rHOrfIY35TGCAfUwggHxAgEBMFQwPTETMBEGCgmSJomT8ixk
# ARkWA0xBQjEUMBIGCgmSJomT8ixkARkWBFpFUk8xEDAOBgNVBAMTB1plcm9TQ0EC
# E1gAAAH5oOvjAv3166MAAQAAAfkwCQYFKw4DAhoFAKB4MBgGCisGAQQBgjcCAQwx
# CjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGC
# NwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFMfRMupGMv+pp6If
# i8OdU9PPsxsZMA0GCSqGSIb3DQEBAQUABIIBALm6TXCc+4gzNky3JUE/kD9xoAao
# EpvYy+qoBI1AUPcbr2mILy4R9kW03icdf16qlMaONH2O3/F23U+UzhT2Xlw7mVqc
# +CBHZUUpzHptW1xVDa2f865MGTnMNmJkuC8bmzJi0ihgGWvvstP1SD9WeFefyMRO
# xypYvPCC+8eCCUP1TmtXuRoYdkW+PW2eXbMiLj7pvMKy6oi9EK+DkgX4YFSt3OU+
# lOFi18/2hhLrz2N7ozpUBcqAZd/6csPD0PHTWmOC/ltik5UXybUDZutr5WJ7zMgN
# rI2mtu9LVIMpifi/QWMuyxEcD8UQ/s8q7OIharboYYe5DzcElDFZdDUTz+A=
# SIG # End signature block
