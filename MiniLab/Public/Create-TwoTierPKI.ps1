<#
    .SYNOPSIS
        This function creates a new Enterprise Root Certificate Authority and new Enterprise Subordinate/Intermediate/Issuing
        Certification Authority on a Domain. If you do not want to create the Root and Subordinate CAs on an existing
        domain, this function is capable of creating a brand new domain and deploying the CAs to that new domain.

    .DESCRIPTION
        This function is an example of 'Service Deployment' function that can be found within the MiniLab Module. A
        'Service Deployment' function is responsible for deploying as many servers as is necessary to get a particular
        service working on a domain/network. This may involve a myriad of feature/role installations and configuration
        setttings across multiple servers.

    .NOTES

    .PARAMETER CreateNewVMs
        This parameter is OPTIONAL.

        This parameter is a switch. If used, new Windows 2016 Standard Server Virtual Machines will be deployed
        to the localhost. If Hyper-V is not installed, it will be installed (and you will need to restart the localhost
        before proceeding).

    .PARAMETER VMStorageDirectory
        This parameter is OPTIONAL, but becomes MANDATORY if the -CreateNewVMs parameter is used.

        This parameter takes a string that represents the full path to a directory on a LOCAL drive that will contain all
        new VM files (configuration, vhd(x), etc.)

    .PARAMETER Windows2016VagrantBox
        This parameter is OPTIONAL, but becomes MANDATORY if the -CreateNewVMs parameter is used.

        This parameter takes a string that represents the name of a Vagrant Box that can be downloaded from
        https://app.vagrantup.com/boxes/search. Default value is "jborean93/WindowsServer2016". Another good
        Windows 2016 Server Vagrant Box is "StefanScherer/windows_2016".

        You can alternatively specify a Windows 2012 R2 Standard Server Vagrant Box if desired.

    .PARAMETER ExistingDomain
        This parameter is OPTIONAL, however, either this parameter or the -NewDomain parameter are MANDATORY.

        This parameter takes a string that represents the name of the domain that the Root and Subordinate CAs will
        join (if they aren't already).

        Example: alpha.lab

    .PARAMETER NewDomain
        This parameter is OPTIONAL, however, either this parameter or the -ExistingDomain parameter are MANDATORY.

        This parameter takes a string that represents the name of the domain that the Root and Subordinate CAs will
        join (if they aren't already).
        
        Example: alpha.lab

    .PARAMETER DomainAdminCredentials
        This parameter is MANDATORY.

        This parameter takes a PSCredential. The Domain Admin Credentials will be used to join the Subordinate CA Server to the domain
        as well as configre the new Subordinate CA. This means that the Domain Account provided to this parameter MUST be a member
        of the following Security Groups in Active Directory:
            - Domain Admins
            - Domain Users
            - Enterprise Admins
            - Group Policy Creator Owners
            - Schema Admins

        If you are creating a New Domain, these credentials will be used to create a new Domain Account that is a member of the
        aforementioned Security Groups.

    .PARAMETER PSRemotingCredentials
        This parameter is MANDATORY.

        This parameter takes a PSCredential.

        The credential provided to this parameter should correspond to a User Account that has permission to
        remote into ALL target Windows Servers. If your target servers are Vagrant Boxes (which is what will be deployed
        if you use the -CreateNewVMs switch), then the value for this parameter should be created via:

            $VagrantVMPassword = ConvertTo-SecureString 'vagrant' -AsPlainText -Force
            $VagrantVMAdminCreds = [pscredential]::new("vagrant",$VagrantVMPassword)

    .PARAMETER LocalAdministratorAccountCredentials
        This parameter is OPTIONAL, however, is you are creating a New Domain, then this parameter is MANDATORY.

        This parameter takes a PSCredential.

        The credential provided to this parameter will be applied to the Local Built-In Administrator Account on the
        target Windows Server. In other words, the pscredential provided to this parameter does NOT need to match
        the current UserName/Password of the Local Administrator Account on the target Windows Server, because the
        pscredential provided to this parameter will overwrite whatever the existing credentials are.

    .PARAMETER DCIsRootCA
        This parameter is OPTIONAL.

        This parameter is a switch. If used, the  Root CA will be installed on the Primary Domain Controller. This is not
        best practice, but if you have limited hardware resources, this could come in handy.

    .PARAMETER IPofServerToBeDomainController
        This parameter is OPTIONAL.

        This parameter takes a string that represents an IPv4 Address referring to an EXISTING Windows Server on the network
        that will become the new Primary Domain Controller.

    .PARAMETER IPOfServerToBeRootCA
        This parameter is OPTIONAL.

        This parameter takes a string that represents an IPv4 Address referring to an EXISTING Windows Server on the network
        that will become the new Root CA.
    
    .PARAMETER IPOfServerToBeSubCA
        This parameter is OPTIONAL.

        This parameter takes a string that represents an IPv4 Address referring to an EXISTING Windows Server on the network
        that will become the new Subordinate CA.

    .PARAMETER PrimaryHyperVHostIPOverride
        This parameter is OPTIONAL.

        This parameter takes a string that represents an IPv4 Address that you would like to use as your External Netowrk on your
        Hyper-V host.

    .PARAMETER SkipHyperVInstallCheck
        This parameter is OPTIONAL.

        This parameter is a switch. If used, this function will not check to make sure Hyper-V is installed on the localhost.

    .EXAMPLE
        # Create a New Domain With 3 Servers - Primary Domain Controller, Root CA, and Subordinate CA
        # Open an elevated PowerShell Session, import the module, and -

        PS C:\Users\zeroadmin> $VagrantVMPassword = ConvertTo-SecureString 'vagrant' -AsPlainText -Force
        PS C:\Users\zeroadmin> $VagrantVMAdminCreds = [pscredential]::new("vagrant",$VagrantVMPassword)
        PS C:\Users\zeroadmin> $DomainAdminCreds = [pscredential]::new("alpha\alphaadmin",$(Read-Host 'Enter Passsword' -AsSecureString))
        Enter Passsword: ************
        PS C:\Users\zeroadmin> $LocalAdminAccountCreds = [pscredential]::new("Administrator",$(Read-Host 'Enter Passsword' -AsSecureString))
        Enter Passsword: **************
        PS C:\Users\zeroadmin> $CreateTwoTierPKISplatParams = @{
        >> CreateNewVMs                            = $True
        >> VMStorageDirectory                      = "H:\VirtualMachines"
        >> NewDomain                               = "alpha.lab"
        >> PSRemotingCredentials                   = $VagrantVMAdminCreds
        >> DomainAdminCredentials                  = $DomainAdminCreds
        >> LocalAdministratorAccountCredentials    = $LocalAdminAccountCreds
        >> }
        PS C:\Users\zeroadmin> Create-TwoTierPKI @CreateTwoTierPKISplatParams

    .EXAMPLE
        # Create a New Domain With 2 Servers - Primary Domain Controller (which will also be the Root CA), and Subordinate CA
        # Open an elevated PowerShell Session, import the module, and -

        PS C:\Users\zeroadmin> $VagrantVMPassword = ConvertTo-SecureString 'vagrant' -AsPlainText -Force
        PS C:\Users\zeroadmin> $VagrantVMAdminCreds = [pscredential]::new("vagrant",$VagrantVMPassword)
        PS C:\Users\zeroadmin> $DomainAdminCreds = [pscredential]::new("alpha\alphaadmin",$(Read-Host 'Enter Passsword' -AsSecureString))
        Enter Passsword: ************
        PS C:\Users\zeroadmin> $LocalAdminAccountCreds = [pscredential]::new("Administrator",$(Read-Host 'Enter Passsword' -AsSecureString))
        Enter Passsword: **************
        PS C:\Users\zeroadmin> $CreateTwoTierPKISplatParams = @{
        >> CreateNewVMs                            = $True
        >> VMStorageDirectory                      = "H:\VirtualMachines"
        >> NewDomain                               = "alpha.lab"
        >> PSRemotingCredentials                   = $VagrantVMAdminCreds
        >> DomainAdminCredentials                  = $DomainAdminCreds
        >> LocalAdministratorAccountCredentials    = $LocalAdminAccountCreds
        >> SkipHyperVInstallCheck                  = $True
        >> DCIsRootCA                              = $True
        >> }
        PS C:\Users\zeroadmin> Create-TwoTierPKI @CreateTwoTierPKISplatParams

    .EXAMPLE
        # Add Two-Tier PKI to your Existing Domain
        # IMPORTANT NOTE: If you can't resolve the -ExistingDomain from the localhost, be sure to use the -IPOfServerToBeDomainController
        # parameter with the IP Address of an EXISTING Domain Controller on the domain specified by -ExistingDomain

        PS C:\Users\zeroadmin> $VagrantVMPassword = ConvertTo-SecureString 'vagrant' -AsPlainText -Force
        PS C:\Users\zeroadmin> $VagrantVMAdminCreds = [pscredential]::new("vagrant",$VagrantVMPassword)
        PS C:\Users\zeroadmin> $DomainAdminCreds = [pscredential]::new("alpha\alphaadmin",$(Read-Host 'Enter Passsword' -AsSecureString))
        Enter Passsword: ************
        PS C:\Users\zeroadmin> $LocalAdminAccountCreds = [pscredential]::new("Administrator",$(Read-Host 'Enter Passsword' -AsSecureString))
        Enter Passsword: **************
        PS C:\Users\zeroadmin> $CreateTwoTierPKISplatParams = @{
        >> CreateNewVMs                            = $True
        >> VMStorageDirectory                      = "H:\VirtualMachines"
        >> ExistingDomain                          = "alpha.lab"
        >> PSRemotingCredentials                   = $VagrantVMAdminCreds
        >> DomainAdminCredentials                  = $DomainAdminCreds
        >> }
        PS C:\Users\zeroadmin> Create-TwoTierPKI @CreateTwoTierPKISplatParams


#>
function Create-TwoTierPKI {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$False)]
        [switch]$CreateNewVMs,

        [Parameter(Mandatory=$False)]
        [string]$VMStorageDirectory,

        [Parameter(Mandatory=$False)]
        [string]$Windows2016VagrantBox = "jborean93/WindowsServer2016", # Alternate - StefanScherer/windows_2016

        [Parameter(Mandatory=$False)]
        [ValidatePattern("^([a-z0-9]+(-[a-z0-9]+)*\.)+([a-z]){2,}$")]
        [string]$NewDomain,

        [Parameter(Mandatory=$True)]
        [pscredential]$DomainAdminCredentials, # If creating a New Domain, this will be a New Domain Account

        [Parameter(Mandatory=$False)]
        [pscredential]$LocalAdministratorAccountCredentials,

        [Parameter(Mandatory=$False)]
        [pscredential]$PSRemotingCredentials, # These credentials must grant access to ALL Servers

        [Parameter(Mandatory=$False)]
        [string]$ExistingDomain,

        [Parameter(Mandatory=$False)]
        [switch]$DCIsRootCA,

        [Parameter(Mandatory=$False)]
        [string]$IPofServerToBeDomainController,

        [Parameter(Mandatory=$False)]
        [string]$IPofServerToBeRootCA,

        [Parameter(Mandatory=$False)]
        [string]$IPofServerToBeSubCA,

        [Parameter(Mandatory=$False)]
        [string]$PrimaryHyperVHostIPOverride,

        [Parameter(Mandatory=$False)]
        [switch]$SkipHyperVInstallCheck
    )

    #region >> Helper Functions

    # TestIsValidIPAddress
    # ResolveHost
    # GetDomainController
    # Deploy-HyperVVagrantBoxManually
    # Get-VagrantBoxManualDownload
    # New-DomainController
    # New-RootCA
    # New-SubordinateCA

    #endregion >> Helper Functions

    #region >> Prep

    $StartTime = Get-Date

    $ElevationCheck = [System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    if (!$ElevationCheck) {
        Write-Error "You must run the build.ps1 as an Administrator (i.e. elevated PowerShell Session)! Halting!"
        $global:FunctionResult = "1"
        return
    }

    $PrimaryIfIndex = $(Get-CimInstance Win32_IP4RouteTable | Where-Object {
        $_.Destination -eq '0.0.0.0' -and $_.Mask -eq '0.0.0.0'
    } | Sort-Object Metric1)[0].InterfaceIndex
    $NicInfo = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object {$_.InterfaceIndex -eq $PrimaryIfIndex}
    $PrimaryIP = $NicInfo.IPAddress | Where-Object {TestIsValidIPAddress -IPAddress $_}

    if ($PrimaryHyperVHostIPOverride) {
        if (!$(TestIsValidIPAddress -IPAddress $PrimaryHyperVHostIPOverride)) {
            Write-Error "'$PrimaryHyperVHostIPOverride' is not a valid IPv4 ip address! Halting!"
            $global:FunctionResult = "1"
            return
        }
        $PrimaryIP = $PrimaryHyperVHostIPOverride
    }

    if ($($PSBoundParameters['CreateNewVMs'] -or $PSBoundParameters['NewDomain']) -and
    !$PSBoundParameters['VMStorageDirectory']
    ) {
        $VMStorageDirectory = Read-Host -Prompt "Please enter the full path to the directory where all VM files will be stored"
    }

    if (!$PSBoundParameters['CreateNewVMs'] -and
    $($PSBoundParameters['VMStorageDirectory'] -or $PSBoundParameters['NewDomain'])
    ) {
        $CreateNewVMs = $True
    }

    if ($PSBoundParameters['NewDomain'] -and !$PSBoundParameters['LocalAdministratorAccountCredentials']) {
        if (!$IPofServerToBeDomainController) {
            $PromptMsg = "Please enter the *desired* password for the Local 'Administrator' account on the server that will become the new Domain Controller"
        }
        else {
            $PromptMsg = "Please enter the password for the Local 'Administrator' Account on $IPofServerToBeDomainController"
        }
        $LocalAdministratorAccountPassword = Read-Host -Prompt $PromptMsg -AsSecureString
        $LocalAdministratorAccountCredentials = [pscredential]::new("Administrator",$LocalAdministratorAccountPassword)
    }

    if ($($PSBoundParameters['IPofServerToBeRootCA'] -and !$PSBoundParameters['IPofServerToBeSubCA']) -or
    $(!$PSBoundParameters['IPofServerToBeRootCA'] -and $PSBoundParameters['IPofServerToBeSubCA'])
    ) {
        Write-Error "You must use BOTH -IPofServerToBeRootCA and -IPofServerToBeSubCA parameters or NEITHER of them! Halting!"
        $global:FunctionResult = "1"
        return
    }
    
    if ($PSBoundParameters['NewDomain'] -and $PSBoundParameters['ExistingDomain']) {
        Write-Error "Please use *either* the -NewDomain parameter *or* the -ExistingDomain parameter! Halting!"
        $global:FunctionResult = "1"
        return
    }

    if (!$PSBoundParameters['NewDomain'] -and !$PSBoundParameters['ExistingDomain']) {
        Write-Error "The $($MyInvocation.MyCommand.Name) function requires either the -ExistingDomain or the -NewDomain parameters! Halting!"
        $global:FunctionResult = "1"
        return
    }

    if (!$CreateNewVMs -and $PSBoundParameters['NewDomain'] -and !$PSBoundParameters['IPofServerToBeDomainController']) {
        $PromptMsg = "Please enter the IP Address of the existing Windows Server that will become the new Domain Controller"
        $IPofServerToBeDomainController = Read-Host -Prompt $PromptMsg
        while (![bool]$(TestIsValidIPAddress -IPAddress $IPofServerToBeDomainController)) {
            Write-Warning "'$IPofServerToBeDomainController' is NOT a valid IPv4 address!"
            $IPofServerToBeDomainController = Read-Host -Prompt $PromptMsg
        }
    }

    if ($CreateNewVMs -and 
    $($PSBoundParameters['IPofServerToBeDomainController'] -or $PSBoundParameters['ExistingDomain']) -and
    $PSBoundParameters['IPofServerToBeRootCA'] -and $PSBoundParameters['IPofServerToBeSubCA']
    ) {
        $ErrMsg = "The parameters -IPofServerToBeDomainController, -IPofServerToBeRootCA, and " +
        "-IPofServerToBeSubCA were used in conjunction with parameters that indicate that new VMs " +
        "should be deployed (i.e. -CreateNewVMs, -VMStorageDirectory, or -NewDomain). Please only " +
        "use -IPofServer* parameters if those servers are already exist. Halting!"
        Write-Error $ErrMsg
        $global:FunctionResult = "1"
        return
    }

    if (!$CreateNewVMs -and !$PSBoundParameters['IPofServerToBeRootCA']) {
        $PromptMsg = = "Please enter the IP Address of the existing Windows Server that will become the new Root CA"
        $IPofServerToBeRootCA = Read-Host -Prompt $PromptMsg
        while (![bool]$(TestIsValidIPAddress -IPAddress $IPofServerToBeRootCA)) {
            Write-Warning "'$IPofServerToBeRootCA' is NOT a valid IPv4 address!"
            $IPofServerToBeRootCA = Read-Host -Prompt $PromptMsg
        }
    }

    if (!$CreateNewVMs -and !$PSBoundParameters['IPofServerToBeSubCA']) {
        $PromptMsg = = "Please enter the IP Address of the existing Windows Server that will become the new Root CA"
        $IPofServerToBeSubCA = Read-Host -Prompt $PromptMsg
        while (![bool]$(TestIsValidIPAddress -IPAddress $IPofServerToBeSubCA)) {
            Write-Warning "'$IPofServerToBeSubCA' is NOT a valid IPv4 address!"
            $IPofServerToBeSubCA = Read-Host -Prompt $PromptMsg
        }
    }

    if ($PSBoundParameters['IPofServerToBeDomainController'] -and $PSBoundParameters['IPofServerToBeRootCA']) {
        if ($IPofServerToBeDomainController -eq $IPofServerToBeRootCA) {
            $DCIsRootCA = $True
        }
    }

    if (!$PSBoundParameters['NewDomain']) {
        if (!$PSBoundParameters['IPofServerToBeDomainController']) {
            # Make sure we can Resolve the Domain/Domain Controller
            try {
                [array]$ResolveDomain = Resolve-DNSName -Name $ExistingDomain -ErrorAction Stop
                $IPofServerToBeDomainController = $ResolveDomain[0].IPAddress
            }
            catch {
                Write-Error $_
                $global:FunctionResult = "1"
                return
            }
        }
        if (!$(TestIsValidIPAddress -IPAddress $IPofServerToBeDomainController)) {
            Write-Error "'$IPofServerToBeDomainController' is NOT a valid IPv4 address! Halting!"
            $global:FunctionResult = "1"
            return
        }
    }

    $FunctionsForRemoteUse = $script:FunctionsForSBUse

    $CreateDCSplatParams = @{
        PSRemotingCredentials                   = $PSRemotingCredentials
        DomainAdminCredentials                  = $DomainAdminCredentials
        LocalAdministratorAccountCredentials    = $LocalAdministratorAccountCredentials
    }

    $CreateRootCASplatParams = @{
        PSRemotingCredentials                   = $PSRemotingCredentials
        DomainAdminCredentials                  = $DomainAdminCredentials
    }

    $CreateSubCASplatParams = @{
        PSRemotingCredentials                   = $PSRemotingCredentials
        DomainAdminCredentials                  = $DomainAdminCredentials
    }

    $FinalDomainName = if ($NewDomain) {$NewDomain} else {$ExistingDomain}
    $DomainShortName = $($FinalDomainName -split '\.')[0]

    #endregion >> Prep

    # Create the new VMs if desired
    if ($CreateNewVMs) {
        # Check to Make Sure Hyper-V is installed
        if (!$SkipHyperVInstallCheck) {
            try {
                $HyperVFeaturesInstallResults = InstallHyperVFeatures -ParentFunction $MyInvocation.MyCommand.Name
            }
            catch {
                Write-Error $_
                Write-Error "The InstallHyperVFeatures function (as executed by the $($MyInvocation.MyCommand.Name) function) failed! Halting!"
                $global:FunctionResult = "1"
                return
            }
            try {
                $InstallContainersFeatureDismResult = InstallFeatureDism -Feature Containers -ParentFunction $MyInvocation.MyCommand.Name
            }
            catch {
                Write-Error $_
                Write-Error "The InstallFeatureDism function (as executed by the $($MyInvocation.MyCommand.Name) function) failed! Halting!"
                $global:FunctionResult = "1"
                return
            }
    
            if ($HyperVFeaturesInstallResults.InstallResults.Count -gt 0 -or $InstallContainersFeatureDismResult.RestartNeeded) {
                if (!$AllowRestarts) {
                    Write-Warning "You must restart $env:ComputerName before proceeding! Halting!"
                    # IMPORTANT NOTE: The below Write-Output "RestartNeeded" is necessary
                    Write-Output "RestartNeeded"
                    $global:FunctionResult = "1"
                    return
                }
                else {
                    Restart-Computer -Confirm:$False -Force
                }
            }
        }

        #region >> Hardware Resource Check

        # Make sure we have at least 100GB of Storage and 12GB of READILY AVAILABLE Memory
        # Check Storage...
        $LocalDrives = Get-CimInstance Win32_LogicalDisk | Where-Object {$_.Drivetype -eq 3} | foreach {Get-PSDrive $_.DeviceId[0] -ErrorAction SilentlyContinue}
        if ([bool]$(Get-Item $VMStorageDirectory).LinkType) {
            $VMStorageDirectoryDriveLetter = $(Get-Item $VMStorageDirectory).Target[0].Substring(0,1)
        }
        else {
            $VMStorageDirectoryDriveLetter = $VMStorageDirectory.Substring(0,1)
        }

        if ($LocalDrives.Name -notcontains $VMStorageDirectoryDriveLetter) {
            Write-Error "'$VMStorageDirectory' does not appear to be a local drive! VMs MUST be stored on a local drive! Halting!"
            $global:FunctionResult = "1"
            return
        }

        $VMStorageDirectoryDriveInfo = Get-WmiObject Win32_LogicalDisk -ComputerName $env:ComputerName -Filter "DeviceID='$VMStorageDirectoryDriveLetter`:'"
        
        if ($([Math]::Round($VMStorageDirectoryDriveInfo.FreeSpace / 1MB)-2000) -lt 100000) {
            Write-Error "Drive '$VMStorageDirectoryDriveLetter' does not have at least 100GB of free space available! Halting!"
            $global:FunctionResult = "1"
            return
        }

        # Check Memory...
        $OSInfo = Get-CimInstance Win32_OperatingSystem
        $TotalMemory = $OSInfo.TotalVisibleMemorySize
        $MemoryAvailable = $OSInfo.FreePhysicalMemory
        $TotalMemoryInGB = [Math]::Round($TotalMemory / 1MB)
        $MemoryAvailableInGB = [Math]::Round($MemoryAvailable / 1MB)
        if ($MemoryAvailableInGB -lt 12 -and !$ForceWithLowMemory) {
            $MemoryErrorMsg = "The Hyper-V hypervisor $env:ComputerName should have at least 12GB of memory " +
            "readily available in order to run the new VMs. It currently only has about $MemoryAvailableInGB " +
            "GB available for immediate use. Halting!"
            Write-Error $MemoryErrorMsg
            $global:FunctionResult = "1"
            return
        }

        #endregion >> Hardware Resource Check

        #region >> Deploy New VMs

        $StartVMDeployment = Get-Date

        # Prepare To Manage .box Files
        if (!$(Test-Path "$VMStorageDirectory\BoxDownloads")) {
            $null = New-Item -ItemType Directory -Path "$VMStorageDirectory\BoxDownloads" -Force
        }
        $BoxNameRegex = [regex]::Escape($($Windows2016VagrantBox -split '/')[0])
        $BoxFileAlreadyPresentCheck = Get-ChildItem "$VMStorageDirectory\BoxDownloads" -File -Filter "*.box" | Where-Object {$_.Name -match $BoxNameRegex}
        $DecompressedBoxDirectoryPresentCheck = Get-ChildItem "$VMStorageDirectory\BoxDownloads" -Directory | Where-Object {$_.Name -match $BoxNameRegex}
        if ([bool]$DecompressedBoxDirectoryPresentCheck) {
            $DecompressedBoxDirectoryItem = $DecompressedBoxDirectoryPresentCheck
            $DecompressedBoxDir = $DecompressedBoxDirectoryItem.FullName
        }
        elseif ([bool]$BoxFileAlreadyPresentCheck) {
            $BoxFileItem = $BoxFileAlreadyPresentCheck
            $BoxFilePath = $BoxFileItem.FullName
        }
        else {
            $BoxFileItem = Get-VagrantBoxManualDownload -VagrantBox $Windows2016VagrantBox -VagrantProvider "hyperv" -DownloadDirectory "$VMStorageDirectory\BoxDownloads"
            $BoxFilePath = $BoxFileItem.FullName
        }

        if ([Environment]::OSVersion.Version -lt [version]"10.0.17063") {
            if (![bool]$(Get-Command bsdtar -ErrorAction SilentlyContinue)) {
                # Download bsdtar from latest MSYS2 available on pldmgg github
                $WindowsNativeLinuxUtilsZipUrl = "https://github.com/pldmgg/WindowsNativeLinuxUtils/raw/master/MSYS2_20161025/bsdtar.zip"
                Invoke-WebRequest -Uri $WindowsNativeLinuxUtilsZipUrl -OutFile "$HOME\Downloads\bsdtar.zip"
                Expand-Archive -Path "$HOME\Downloads\bsdtar.zip" -DestinationPath "$HOME\Downloads" -Force
                $BsdTarDirectory = "$HOME\Downloads\bsdtar"
    
                if ($($env:Path -split ";") -notcontains $BsdTarDirectory) {
                    if ($env:Path[-1] -eq ";") {
                        $env:Path = "$env:Path$BsdTarDirectory"
                    }
                    else {
                        $env:Path = "$env:Path;$BsdTarDirectory"
                    }
                }
                $TarCmd = "bsdtar"
            }
            else {
                $TarCmd = "tar"
            }
        }
        
        if ($BoxFileItem) {
            $DecompressedBoxDir = "$VMStorageDirectory\BoxDownloads\$($BoxFileItem.BaseName)"
            if (!$(Test-Path $DecompressedBoxDir)) {
                $null = New-Item -ItemType Directory -Path $DecompressedBoxDir
            }

            # Extract the .box File
            Push-Location $DecompressedBoxDir

            if ($PSVersionTable.PSEdition -eq "Core") {
                <#
                GetWinPSInCore -ScriptBlock {
                    $FunctionsForRemoteUse | foreach {Invoke-Expression $_}

                    while ([bool]$(GetFileLockProcess -FilePath $BoxFilePath -ErrorAction SilentlyContinue)) {
                        Write-Host "$BoxFilePath is currently being used by another process...Waiting for it to become available"
                        Start-Sleep -Seconds 5
                    }
                }
                #>
                Invoke-WinCommand -ComputerName localhost -ScriptBlock {
                    $args[0] | foreach {Invoke-Expression $_}

                    while ([bool]$(GetFileLockProcess -FilePath $args[1] -ErrorAction SilentlyContinue)) {
                        Write-Host "'$($args[1])' is currently being used by another process...Waiting for it to become available"
                        Start-Sleep -Seconds 5
                    }
                } -ArgumentList $FunctionsForRemoteUse,$BoxFilePath
            }
            else {
                while ([bool]$(GetFileLockProcess -FilePath $BoxFilePath -ErrorAction SilentlyContinue)) {
                    Write-Host "$BoxFilePath is currently being used by another process...Waiting for it to become available"
                    Start-Sleep -Seconds 5
                }
            }

            try {
                #Write-Host "Extracting .box file..."
                
                $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
                $ProcessInfo.WorkingDirectory = $DecompressedBoxDir
                $ProcessInfo.FileName = $TarCmd
                $ProcessInfo.RedirectStandardError = $true
                $ProcessInfo.RedirectStandardOutput = $true
                $ProcessInfo.UseShellExecute = $false
                $ProcessInfo.Arguments = "-xzvf $BoxFilePath"
                $Process = New-Object System.Diagnostics.Process
                $Process.StartInfo = $ProcessInfo
                $Process.Start() | Out-Null
                # Below $FinishedInAlottedTime returns boolean true/false
                # 1800000 ms is 30 minutes
                $FinishedInAlottedTime = $Process.WaitForExit(1800000)
                if (!$FinishedInAlottedTime) {
                    $Process.Kill()
                }
                $stdout = $Process.StandardOutput.ReadToEnd()
                $stderr = $Process.StandardError.ReadToEnd()
                $AllOutput = $stdout + $stderr
    
                if ($stderr) {
                    if ($stderr -match "failed") {
                        throw $stderr
                    }
                    else {
                        Write-Verbose $stderr
                    }
                }
            }
            catch {
                Write-Error $_
                #Remove-Item $BoxFilePath -Force
                $global:FunctionResult = "1"
                return
            }

            Pop-Location
        }

        # Make sure $BoxFilePath doesn't exist as a variable so that the below VM Deployment scriptblock
        # copies the $DecompressedBoxDir
        Remove-Variable -Name 'BoxFilePath' -Force -ErrorAction SilentlyContinue

        $ErrMsg = "Unable to find the decompressed Vagrant Box directory! Halting!"
        if (!$DecompressedBoxDir) {
            Write-Error $ErrMsg
            $global:FunctionResult = "1"
            return
        }
        if ($DecompressedBoxDir) {
            if (!$(Test-Path $DecompressedBoxDir)) {
                Write-Error $ErrMsg
                $global:FunctionResult = "1"
                return
            }
        }

        $NewVMDeploySB = {
            $DeployBoxSplatParams = @{
                VagrantBox                  = $Windows2016VagrantBox
                CPUs                        = 2
                Memory                      = 4096
                VagrantProvider             = "hyperv"
                VMName                      = $UpdatedVMName
                VMDestinationDirectory      = $VMStorageDirectory
                CopyDecompressedDirectory   = $True
                SkipHyperVInstallCheck      = $True
            }
            
            if ($DecompressedBoxDir) {
                if ($(Get-Item $DecompressedBoxDir).PSIsContainer) {
                    $DeployBoxSplatParams.Add('DecompressedBoxDirectory',$DecompressedBoxDir)
                }
            }
            if ($BoxFilePath) {
                if (-not $(Get-Item $BoxFilePath).PSIsContainer) {
                    $DeployBoxSplatParams.Add('BoxFilePath',$BoxFilePath)
                }
            }
            
            Write-Host "Deploying Hyper-V Vagrant Box..."
            $DeployBoxResult = Deploy-HyperVVagrantBoxManually @DeployBoxSplatParams
            $DeployBoxResult
        }

        if ($NewDomain -and !$IPofServerToBeDomainController) {
            $DomainShortName = $($NewDomain -split "\.")[0]
            $NewDCVMName = $UpdatedVMName = $DomainShortName + 'DC1'
            Write-Host "Deploying New Domain Controller VM '$UpdatedVMName'..."

            if ($global:RSSyncHash) {
                $RunspaceNames = $($global:RSSyncHash.Keys | Where-Object {$_ -match "Result$"}) | foreach {$_ -replace 'Result',''}
                $NewDCVMDeployJobName = NewUniqueString -PossibleNewUniqueString "NewDCVM" -ArrayOfStrings $RunspaceNames
            }
            else {
                $NewDCVMDeployJobName = "NewDCVM"
            }

            $NewDCVMDeployJobSplatParams = @{
                RunspaceName    = $NewDCVMDeployJobName
                Scriptblock     = $NewVMDeploySB
            }
            $null = New-Runspace @NewDCVMDeployJobSplatParams

            <#
            $NewDCVMDeployJobSplatParams = @{
                Name            = $NewDCVMDeployJobName
                Scriptblock     = $NewVMDeploySB
                ArgumentList    = $FunctionsForRemoteUse
            }
            $NewDCVMDeployJobInfo = Start-Job @NewDCVMDeployJobSplatParams
            #>
        }
        if (!$IPofServerToBeRootCA -and !$DCIsRootCA) {
            if ($NewDomain) {
                $DomainShortName = $($NewDomain -split "\.")[0]
            }
            if ($ExistingDomain) {
                $DomainShortName = $($ExistingDomain -split "\.")[0]
            }
            $NewRootCAVMName = $UpdatedVMName = $DomainShortName + "RootCA"
            Write-Host "Deploying New Root CA VM '$UpdatedVMName'..."

            if ($global:RSSyncHash) {
                $RunspaceNames = $($global:RSSyncHash.Keys | Where-Object {$_ -match "Result$"}) | foreach {$_ -replace 'Result',''}
                $NewRootCAVMDeployJobName = NewUniqueString -PossibleNewUniqueString "NewRootCAVM" -ArrayOfStrings $RunspaceNames
            }
            else {
                $NewRootCAVMDeployJobName = "NewRootCAVM"
            }

            $NewRootCAVMDeployJobSplatParams = @{
                RunspaceName    = $NewRootCAVMDeployJobName
                Scriptblock     = $NewVMDeploySB
            }
            $null = New-Runspace @NewRootCAVMDeployJobSplatParams

            <#
            $NewRootCAVMDeployJobSplatParams = @{
                Name            = $NewRootCAVMDeployJobName
                Scriptblock     = $NewVMDeploySB
                ArgumentList    = $FunctionsForRemoteUse
            }
            $NewRootCAVMDeployJobInfo = Start-Job @NewRootCAVMDeployJobSplatParams
            #>
        }
        if (!$IPofServerToBeSubCA) {
            if ($NewDomain) {
                $DomainShortName = $($NewDomain -split "\.")[0]
            }
            if ($ExistingDomain) {
                $DomainShortName = $($ExistingDomain -split "\.")[0]
            }
            $NewSubCAVMName = $UpdatedVMName = $DomainShortName + "SubCA"
            Write-Host "Deploying New Subordinate CA VM '$UpdatedVMName'..."

            if ($global:RSSyncHash) {
                $RunspaceNames = $($global:RSSyncHash.Keys | Where-Object {$_ -match "Result$"}) | foreach {$_ -replace 'Result',''}
                $NewSubCAVMDeployJobName = NewUniqueString -PossibleNewUniqueString "NewSubCAVM" -ArrayOfStrings $RunspaceNames
            }
            else {
                $NewSubCAVMDeployJobName = "NewSubCAVM"
            }

            $NewSubCAVMDeployJobSplatParams = @{
                RunspaceName    = $NewSubCAVMDeployJobName
                Scriptblock     = $NewVMDeploySB
            }
            $null = New-Runspace @NewSubCAVMDeployJobSplatParams

            <#
            $NewSubCAVMDeployJobSplatParams = @{
                Name            = $NewSubCAVMDeployJobName
                Scriptblock     = $NewVMDeploySB
                ArgumentList    = $FunctionsForRemoteUse
            }
            $NewSubCAVMDeployJobInfo = Start-Job @NewSubCAVMDeployJobSplatParams
            #>
        }

        [System.Collections.ArrayList]$ResultProperties = @()
        if ($NewDomain -and !$IPofServerToBeDomainController) {
            $NewDCResultProperty = $NewDCVMDeployJobName + "Result"
            $null = $ResultProperties.Add($NewDCResultProperty)
        }
        if (!$IPofServerToBeRootCA -and !$DCIsRootCA) {
            $NewRootCAResultProperty = $NewRootCAVMDeployJobName + "Result"
            $null = $ResultProperties.Add($NewRootCAResultProperty)
        }
        if (!$IPofServerToBeSubCA) {
            $NewSubCAResultProperty = $NewSubCAVMDeployJobName + "Result"
            $null = $ResultProperties.Add($NewSubCAResultProperty)
        }

        # VM deployment operations have 60 minutes to complete...
        $Counter = 0
        while (!$VMsReady -and $Counter -le 60) {
            [System.Collections.ArrayList]$ResultCollection = @()
            foreach ($ResultProp in $ResultProperties) {
                if ($global:RSSyncHash.$ResultProp.Errors.Count -gt 0 -and $global:RSSyncHash.$ResultProp.Done -eq $True) {
                    $Errmsg = "One or more errors occurred with the Deploy-HyperVVagrantBoxManually " +
                    "function within the Runspaces. Please inspect the 'Errors' property in the " +
                    "`$global:RSSynchHash object. Halting!"
                    Write-Error $ErrMsg
                    $global:FunctionResult = "1"
                    return
                }

                if ($global:RSSyncHash.$ResultProp.Done -ne $True) {
                    Write-Host "Waiting for $ResultProp ..."
                    $null = $ResultCollection.Add($False)
                }
                else {
                    $null = $ResultCollection.Add($True)
                }
            }

            if ($ResultCollection -contains $False -or $ResultCollection.Count -eq 0) {
                Write-Host "VMs not ready. Checking again in 60 seconds ..."
                $VMsReady = $False
                Start-Sleep -Seconds 60
                $Counter++
            }
            else {
                $VMsReady = $True
                Write-Host "VMs are ready to be configured!" -ForegroundColor Green
            }
        }
        if ($Counter -gt 60) {
            Write-Error "VMs were not deployed within 60 minutes! Halting!"
            $global:FunctionResult = "1"
            return
        }

        Write-Host "Waiting for VMs to report their IP Addresses (for up to 30 minutes)..."

        # NOTE: Each VM has 30 minutes to report its IP Address
        $Counter = 0
        if ($NewDomain -and !$IPofServerToBeDomainController) {
            $NewDCVMDeployResult = $global:RSSyncHash.$NewDCResultProperty.Output

            $IPofServerToBeDomainController = $NewDCVMDeployResult.VMIPAddress

            if (!$(TestIsValidIPAddress -IPAddress $IPofServerToBeDomainController)) {
                $VMNetAdapter = Get-VMNetworkAdapter -VMName $NewDCVMName -ErrorAction SilentlyContinue
                $IPofServerToBeDomainController = $NewDCVMIPCheck = $VMNetAdapter.IPAddresses | Where-Object {TestIsValidIPAddress -IPAddress $_}
                while (!$NewDCVMIPCheck -and $Counter -le 60) {
                    Start-Sleep -Seconds 60

                    $VMNetAdapter = Get-VMNetworkAdapter -VMName $NewDCVMName -ErrorAction SilentlyContinue
                    $IPofServerToBeDomainController = $NewDCVMIPCheck = $VMNetAdapter.IPAddresses | Where-Object {TestIsValidIPAddress -IPAddress $_}
                    $Counter++
                }
            }
        }

        $Counter = 0
        if (!$IPofServerToBeRootCA) {
            if ($DCIsRootCA) {
                $IPofServerToBeRootCA = $IPofServerToBeDomainController
            }

            if (!$DCIsRootCA) {
                $NewRootCAVMDeployResult = $global:RSSyncHash.$NewRootCAResultProperty.Output

                $IPofServerToBeRootCA = $NewRootCAVMDeployResult.VMIPAddress

                if (!$(TestIsValidIPAddress -IPAddress $IPofServerToBeRootCA)) {
                    $VMNetAdapter = Get-VMNetworkAdapter -VMName $NewRootCAVMName -ErrorAction SilentlyContinue
                    $IPofServerToBeRootCA = $NewRootCAVMIPCheck = $VMNetAdapter.IPAddresses | Where-Object {TestIsValidIPAddress -IPAddress $_}
                    while (!$NewRootCAVMIPCheck -and $Counter -le 60) {
                        Start-Sleep -Seconds 60
    
                        $VMNetAdapter = Get-VMNetworkAdapter -VMName $NewRootCAVMName -ErrorAction SilentlyContinue
                        $IPofServerToBeRootCA = $NewRootCAVMIPCheck = $VMNetAdapter.IPAddresses | Where-Object {TestIsValidIPAddress -IPAddress $_}
                        $Counter++
                    }
                }
            }
        }

        $Counter = 0
        if (!$IPofServerToBeSubCA) {
            $NewSubCAVMDeployResult = $global:RSSyncHash.$NewSubCAResultProperty.Output

            $IPofServerToBeSubCA = $NewRSubCAVMDeployResult.VMIPAddress

            if (!$(TestIsValidIPAddress -IPAddress $IPofServerToBeSubCA)) {
                $VMNetAdapter = Get-VMNetworkAdapter -VMName $NewSubCAVMName -ErrorAction SilentlyContinue
                $IPofServerToBeSubCA = $NewSubCAVMIPCheck = $VMNetAdapter.IPAddresses | Where-Object {TestIsValidIPAddress -IPAddress $_}
                while (!$NewSubCAVMIPCheck -and $Counter -le 60) {
                    Start-Sleep -Seconds 60

                    $VMNetAdapter = Get-VMNetworkAdapter -VMName $NewSubCAVMName -ErrorAction SilentlyContinue
                    $IPofServerToBeSubCA = $NewSubCAVMIPCheck = $VMNetAdapter.IPAddresses | Where-Object {TestIsValidIPAddress -IPAddress $_}
                    $Counter++
                }
            }
        }

        [System.Collections.ArrayList]$VMsNotReportingIP = @()
        if (!$(TestIsValidIPAddress -IPAddress $IPofServerToBeDomainController)) {
            $null = $VMsNotReportingIP.Add($NewDCVMName)
        }
        if (!$(TestIsValidIPAddress -IPAddress $IPofServerToBeRootCA)) {
            $null = $VMsNotReportingIP.Add($NewRootCAVMName)
        }
        if (!$(TestIsValidIPAddress -IPAddress $IPofServerToBeSubCA)) {
            $null = $VMsNotReportingIP.Add($NewSubCAVMName)
        }

        if ($VMsNotReportingIP.Count -gt 0) {
            Write-Error "The following VMs did NOT report thier IP Addresses within 30 minutes:`n$($VMsNotReportingIP -join "`n")`nHalting!"
            $global:FunctionResult = "1"
            return
        }

        Write-Host "Finished Deploying New VMs..." -ForegroundColor Green

        if ($NewDomain) {
            Write-Host "IP of DC is $IPOfServerToBeDomainController"
        }
        Write-Host "IP of Root CA is $IPOfServerToBeRootCA"
        Write-Host "IP of Sub CA is $IPOfServerToBeSubCA"

        #region >> Update WinRM/WSMAN

        Write-Host "Updating WinRM/WSMan to allow for PSRemoting to Servers ..."
        try {
            $null = Enable-PSRemoting -Force -ErrorAction Stop
        }
        catch {
            $NICsWPublicProfile = @(Get-NetConnectionProfile | Where-Object {$_.NetworkCategory -eq 0})
            if ($NICsWPublicProfile.Count -gt 0) {
                foreach ($Nic in $NICsWPublicProfile) {
                    Set-NetConnectionProfile -InterfaceIndex $Nic.InterfaceIndex -NetworkCategory 'Private'
                }
            }

            try {
                $null = Enable-PSRemoting -Force
            }
            catch {
                Write-Error $_
                Write-Error "Problem with Enabble-PSRemoting WinRM Quick Config! Halting!"
                $global:FunctionResult = "1"
                return
            }
        }

        # If $env:ComputerName is not part of a Domain, we need to add this registry entry to make sure WinRM works as expected
        if (!$(Get-CimInstance Win32_Computersystem).PartOfDomain) {
            $null = reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f
        }

        # Add the New Server's IP Addresses to $env:ComputerName's TrustedHosts
        $CurrentTrustedHosts = $(Get-Item WSMan:\localhost\Client\TrustedHosts).Value
        [System.Collections.ArrayList][array]$CurrentTrustedHostsAsArray = $CurrentTrustedHosts -split ','

        [System.Collections.ArrayList]$ItemsToAddToWSMANTrustedHosts = @(
            $IPofServerToBeRootCA
            $IPofServerToBeSubCA
        )
        if ($IPofServerToBeDomainController) {
            $null = $ItemsToAddToWSMANTrustedHosts.Add($IPofServerToBeDomainController)
        }
        foreach ($NetItem in $ItemsToAddToWSMANTrustedHosts) {
            if ($CurrentTrustedHostsAsArray -notcontains $NetItem) {
                $null = $CurrentTrustedHostsAsArray.Add($NetItem)
            }
        }
        $UpdatedTrustedHostsString = $($CurrentTrustedHostsAsArray | Where-Object {![string]::IsNullOrWhiteSpace($_)}) -join ','
        Set-Item WSMan:\localhost\Client\TrustedHosts $UpdatedTrustedHostsString -Force

        Write-Host "Finished updating WinRM/WSMan..."

        #endregion >> Update WinRM/WSMAN


        #region >> Make Sure WinRM/WSMan Is Ready on the Remote Hosts

        Write-Host "Attempting New PSSession to Remote Hosts for up to 30 minutes to ensure they are ready..."
        if ($NewDomain) {
            $PSSessionName = NewUniqueString -ArrayOfStrings $(Get-PSSession).Name -PossibleNewUniqueString "ToDC1Check"
            $Counter = 0
            while (![bool]$(Get-PSSession -Name $PSSessionName -ErrorAction SilentlyContinue)) {
                try {
                    $DCPSSession = New-PSSession -ComputerName $IPofServerToBeDomainController -Credential $PSRemotingCredentials -Name $PSSessionName -ErrorAction SilentlyContinue
                    if (![bool]$(Get-PSSession -Name $PSSessionName -ErrorAction SilentlyContinue)) {throw}
                }
                catch {
                    if ($Counter -le 120) {
                        Write-Warning "New-PSSession '$PSSessionName' failed. Trying again in 15 seconds..."
                        Start-Sleep -Seconds 15
                    }
                    else {
                        Write-Error "Unable to create new PSSession to '$PSSessionName' to '$IPofServerToBeDomainController' using account '$($PSRemotingCredentials.UserName)' within 30 minutes! Halting!"
                        $global:FunctionResult = "1"
                        return
                    }
                }
                $Counter++
            }
        }

        $PSSessionName = NewUniqueString -ArrayOfStrings $(Get-PSSession).Name -PossibleNewUniqueString "ToRootCACheck"
        $Counter = 0
        while (![bool]$(Get-PSSession -Name $PSSessionName -ErrorAction SilentlyContinue)) {
            try {
                $RootCAPSSession = New-PSSession -ComputerName $IPofServerToBeRootCA -Credential $PSRemotingCredentials -Name $PSSessionName -ErrorAction SilentlyContinue
                if (![bool]$(Get-PSSession -Name $PSSessionName -ErrorAction SilentlyContinue)) {throw}
            }
            catch {
                if ($Counter -le 120) {
                    Write-Warning "New-PSSession '$PSSessionName' failed. Trying again in 15 seconds..."
                    Start-Sleep -Seconds 15
                }
                else {
                    Write-Error "Unable to create new PSSession to '$PSSessionName' to '$IPofServerToBeRootCA' using account '$($PSRemotingCredentials.UserName)' within 30 minutes! Halting!"
                    $global:FunctionResult = "1"
                    $RootCAPSRemotingFailure = $True
                    return
                }
            }
            $Counter++
        }

        $PSSessionName = NewUniqueString -ArrayOfStrings $(Get-PSSession).Name -PossibleNewUniqueString "ToSubCACheck"
        $Counter = 0
        while (![bool]$(Get-PSSession -Name $PSSessionName -ErrorAction SilentlyContinue)) {
            try {
                $SubCAPSSession = New-PSSession -ComputerName $IPofServerToBeSubCA -Credential $PSRemotingCredentials -Name $PSSessionName -ErrorAction SilentlyContinue
                if (![bool]$(Get-PSSession -Name $PSSessionName -ErrorAction SilentlyContinue)) {throw}
            }
            catch {
                if ($Counter -le 60) {
                    Write-Warning "New-PSSession '$PSSessionName' failed. Trying again in 15 seconds..."
                    Start-Sleep -Seconds 15
                }
                else {
                    Write-Error "Unable to create new PSSession to '$PSSessionName' to '$IPofServerToBeSubCA' using account '$($PSRemotingCredentials.UserName)' within 30 minutes! Halting!"
                    $global:FunctionResult = "1"
                    return
                }
            }
            $Counter++
        }

        # Clear the PSSessions
        Get-PSSession | Remove-PSSession

        $EndVMDeployment = Get-Date

        if ($StartVMDeployment -and $EndVMDeployment) {
            $TotalTime = $EndVMDeployment - $StartVMDeployment
            Write-Host "VM Deployment took $($TotalTime.Hours) hours and $($TotalTime.Minutes) minutes..." -ForegroundColor Yellow
        }

        #endregion >> Make Sure WinRM/WSMan Is Ready on the Remote Hosts
        
        #endregion >> Deploy New VMs
    }

    #region >> Create the Services

    # Finish setting splat params for Create-Domain, Create-RootCA, and Create-SubordinateCA functions...
    if ($NewDomain) {
        $CreateDCSplatParams.Add("IPofServerToBeDomainController",$IPofServerToBeDomainController)
        $CreateDCSplatParams.Add("NewDomain",$FinalDomainName)

        #Write-Host "Splat Params for Create-Domain are:" -ForegroundColor Yellow
        #$CreateDCSplatParams
    }

    $CreateRootCASplatParams.Add("IPofServerToBeRootCA",$IPofServerToBeRootCA)
    $CreateRootCASplatParams.Add("IPofDomainController",$IPofServerToBeDomainController)
    $CreateRootCASplatParams.Add("ExistingDomain",$FinalDomainName)
    #Write-Host "Splat Params for Create-RootCA are:" -ForegroundColor Yellow
    #$CreateRootCASplatParams

    $CreateSubCASplatParams.Add("IPofServerToBeSubCA",$IPofServerToBeSubCA)
    $CreateSubCASplatParams.Add("IPofDomainController",$IPofServerToBeDomainController)
    $CreateSubCASplatParams.Add("IPofRootCA",$IPofServerToBeRootCA)
    $CreateSubCASplatParams.Add("ExistingDomain",$FinalDomainName)
    #Write-Host "Splat Params for Create-SubordinateCA are:" -ForegroundColor Yellow
    #$CreateSubCASplatParams

    if ($NewDomain) {
        try {
            $CreateDCResult = Create-Domain @CreateDCSplatParams
        }
        catch {
            Write-Error $_
            $global:FunctionResult = "1"
            return
        }
    }

    try {
        $CreateRootCAResult = Create-RootCA @CreateRootCASplatParams
    }
    catch {
        Write-Error $_
        $global:FunctionResult = "1"
        return
    }
    
    try {
        $CreateSubCAResult = Create-SubordinateCA @CreateSubCASplatParams
    }
    catch {
        Write-Error $_
        $global:FunctionResult = "1"
        return
    }

    $EndTime = Get-Date
    $TotalAllOpsTime = $EndTime - $StartTime
    Write-Host "All operations for the $($MyInvocation.MyCommand.Name) function took $($TotalAllOpsTime.Hours) hours and $($TotalAllOpsTime.Minutes) minutes" -ForegroundColor Yellow

    $Output = @{
        CreateRootCAResult      = $CreateRootCAResult
        CreateSubCAResult       = $CreateSubCAResult
    }
    if ($CreateDCResult) {
        $Output.Add("CreateDCResult",$CreateDCResult)
    }

    [pscustomobject]$Output

    #end >> Create the Services
}

# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU9ePRJLl9LtY5ncpbmbw5h3k/
# 9JqgggndMIIEJjCCAw6gAwIBAgITawAAADqEP46TDmc/hQAAAAAAOjANBgkqhkiG
# 9w0BAQsFADAwMQwwCgYDVQQGEwNMQUIxDTALBgNVBAoTBFpFUk8xETAPBgNVBAMT
# CFplcm9EQzAxMB4XDTE4MTAxNzIwMTEyNVoXDTIwMTAxNzIwMjEyNVowPTETMBEG
# CgmSJomT8ixkARkWA0xBQjEUMBIGCgmSJomT8ixkARkWBFpFUk8xEDAOBgNVBAMT
# B1plcm9TQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC0crvKbqlk
# 77HGtaVMWpZBOKwb9eSHzZjh5JcfMJ33A9ORwelTAzpRP+N0k/rAoQkauh3qdeQI
# fsqdcrEiingjiOvxaX3lHA5+fVGe/gAnZ+Cc7iPKXJVhw8jysCCld5zIG8x8eHuV
# Z540iNXdI+g2mustl+l5q4kcWukj+iQwtCYEaCgAXB9qlkT33sX0k/07JoSYcGJx
# ++0SHnF0HBw7Gs/lHlyt4biIGtJleOw0iIN2yVD9UrVWMtKrghKPaW31mjYYeN5k
# ckYzBit/Kokxo0m54B4M3aLRPBQdXH1wL6A894BAlUlPM7vrozU2cLrZgcFuEvwM
# 0cLN8mfGKbo5AgMBAAGjggEqMIIBJjASBgkrBgEEAYI3FQEEBQIDAgACMCMGCSsG
# AQQBgjcVAgQWBBTlQTDY2HBi1snaI36s8nvJLv5ZGDAdBgNVHQ4EFgQUkNLPVlgd
# vV0pNGjQxY8gU/mxzMIwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwDgYDVR0P
# AQH/BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAUdpW6phL2RQNF
# 7AZBgQV4tgr7OE0wMQYDVR0fBCowKDAmoCSgIoYgaHR0cDovL3BraS9jZXJ0ZGF0
# YS9aZXJvREMwMS5jcmwwPAYIKwYBBQUHAQEEMDAuMCwGCCsGAQUFBzAChiBodHRw
# Oi8vcGtpL2NlcnRkYXRhL1plcm9EQzAxLmNydDANBgkqhkiG9w0BAQsFAAOCAQEA
# fgu+F49OeWIQAUO9nUN5bYBtmBwU1YOL1X1OtmFPRkwBm4zE+rjMtWOO5MU4Huv3
# f3y2K0BhVWfu12N9nOZW1kO+ENgxwz5rjwR/VtxJzopO5EALJZwwDoOqfQUDgqRN
# xyRh8qX1CM/mPpu9xPi/FeA+3xCd0goKGVRPQD9NBq24ktb9iGWu/vNb5ovGXsU5
# JzDz4drIHrnEy2SM7g9YdRo/IvshBvrQdYKiNIMeB0WxCsUAjqu/J42Nc9LGQcRj
# jJSK4baX1eotcBpy/XjVC0lHhOI+BdirfVRGvTjax7KqJWSem0ccxaw30e3jRQJE
# wnslUecNTfz07DkopxjrxDCCBa8wggSXoAMCAQICE1gAAAJQw22Yn6op/pMAAwAA
# AlAwDQYJKoZIhvcNAQELBQAwPTETMBEGCgmSJomT8ixkARkWA0xBQjEUMBIGCgmS
# JomT8ixkARkWBFpFUk8xEDAOBgNVBAMTB1plcm9TQ0EwHhcNMTkxMTI4MTI1MDM2
# WhcNMjExMTI3MTI1MDM2WjBJMUcwRQYDVQQDEz5aZXJvQ29kZTEzLE9VPURldk9w
# cyxPPVRlY2ggVGFyZ2V0cywgTExDLEw9QnJ5biBNYXdyLFM9UEEsQz1VUzCCASIw
# DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAPYULq1HCD/SgqTajXuWjnzVedBE
# Nc3LQwdDFmOLyrVPi9S9FF3yYDCTywA6wwgxSQGhI8MVWwF2Xdm+e6pLX+957Usk
# /lZGHCNwOMP//vodJUhxcyDZG7sgjjz+3qBl0OhUodZfqlprcVMQERxlIK4djDoP
# HhIBHBm6MZyC9oiExqytXDqbns4B1MHMMHJbCBT7KZpouonHBK4p5ObANhGL6oh5
# GnUzZ+jOTSK4DdtulWsvFTBpfz+JVw/e3IHKqHnUD4tA2CxxA8ofW2g+TkV+/lPE
# 9IryeA6PrAy/otg0MfVPC2FKaHzkaaMocnEBy5ZutpLncwbwqA3NzerGmiMCAwEA
# AaOCApowggKWMA4GA1UdDwEB/wQEAwIHgDAdBgNVHQ4EFgQUW0DvcuEW1X6BD+eQ
# 2AJHO2eur9UwHwYDVR0jBBgwFoAUkNLPVlgdvV0pNGjQxY8gU/mxzMIwgekGA1Ud
# HwSB4TCB3jCB26CB2KCB1YaBrmxkYXA6Ly8vQ049WmVyb1NDQSgyKSxDTj1aZXJv
# U0NBLENOPUNEUCxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNl
# cyxDTj1Db25maWd1cmF0aW9uLERDPXplcm8sREM9bGFiP2NlcnRpZmljYXRlUmV2
# b2NhdGlvbkxpc3Q/YmFzZT9vYmplY3RDbGFzcz1jUkxEaXN0cmlidXRpb25Qb2lu
# dIYiaHR0cDovL3BraS9jZXJ0ZGF0YS9aZXJvU0NBKDIpLmNybDCB5gYIKwYBBQUH
# AQEEgdkwgdYwgaMGCCsGAQUFBzAChoGWbGRhcDovLy9DTj1aZXJvU0NBLENOPUFJ
# QSxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25m
# aWd1cmF0aW9uLERDPXplcm8sREM9bGFiP2NBQ2VydGlmaWNhdGU/YmFzZT9vYmpl
# Y3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0aG9yaXR5MC4GCCsGAQUFBzAChiJodHRw
# Oi8vcGtpL2NlcnRkYXRhL1plcm9TQ0EoMykuY3J0MD0GCSsGAQQBgjcVBwQwMC4G
# JisGAQQBgjcVCIO49D+Em/J5g/GPOIOwtzKG0c14gSeh88wfj9lVAgFkAgEFMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMBsGCSsGAQQBgjcVCgQOMAwwCgYIKwYBBQUHAwMw
# DQYJKoZIhvcNAQELBQADggEBAEfjH/emq+TnlhFss6cNor/VYKPoEeqYgFwzGbul
# dzPdPEBFUNxcreN0b61kxfenAHifvI0LCr/jDa8zGPEOvo8+zB/GWp1Huw/xLMB8
# rfZHBCox3Av0ohjzO5Ac5yCHijZmrwaXV3XKpBncWdC6pfr/O0bIoRMbvV9EWkYG
# fpNaFvR8piUGJ47cLlC+NFTOQcmESOmlsy+v8JeG9OPsnvZLsD6sydajrxRnNlSm
# zbK64OrbSM9gQoA6bjuZ6lJWECCX1fEYDBeZaFrtMB/RTVQLF/btisfDQXgZJ+Tw
# Tjy+YP39D0fwWRfAPSRJ8NcnRw4Ccj3ngHz7e0wR6niCtsMxggH1MIIB8QIBATBU
# MD0xEzARBgoJkiaJk/IsZAEZFgNMQUIxFDASBgoJkiaJk/IsZAEZFgRaRVJPMRAw
# DgYDVQQDEwdaZXJvU0NBAhNYAAACUMNtmJ+qKf6TAAMAAAJQMAkGBSsOAwIaBQCg
# eDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEE
# AYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJ
# BDEWBBSmFVZj1tfxAycHN7rOuBVrFeulyjANBgkqhkiG9w0BAQEFAASCAQCErq4o
# G2fugYfk3mQ3TUzi3F32GzNngi3FZXp4mUvhBHiZKeZeac/XINCfVIS8r/SGg2A9
# KF2caq5o6/LNxo3LdeUtQIHKFLClpoqrDWEJDv/buFdJL7HHZhc4QHkC9y8xnAgA
# aIE3NmFouuxH4yCbokJ06q8MZNHMZnKw5e3u76x7jfDOBLzKLcf08lWZuJZPo2yv
# Jk9V52oHO0KQPkA6NNMah9Fucf5yl08xBjTyqfIA1hTjaMmpSj9T7rkiphOKzi3E
# YF/fZcHq1wnxtm9Qrlpe/reFgXStfUumm84f0VkP0G8RmCwEltLJatMCs9253/R/
# N89SJhNQrgfgE25O
# SIG # End signature block
