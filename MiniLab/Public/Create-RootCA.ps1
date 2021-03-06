<#
    .SYNOPSIS
        This function creates a new Enterprise Root Certification Authority by either...
        
        A) Creating a brand new Windows Server VM; or
        B) Using an existing Windows Server on the network
        
        ...and then running a configuration script over a PS Remoting Session.

    .DESCRIPTION
        See .SYNOPSIS

    .NOTES

    .PARAMETER CreateNewVMs
        This parameter is OPTIONAL.

        This parameter is a switch. If used, a new Windows 2016 Standard Server Virtual Machine will be deployed
        to the localhost. If Hyper-V is not installed, it will be installed (and you will need to reatart the localhost
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
        This parameter is MANDATORY.

        This parameter takes a string that represents the name of the domain that the Root CA will join.
        Example: alpha.lab

    .PARAMETER DomainAdminCredentials
        This parameter is MANDATORY.

        This parameter takes a PSCredential. The Domain Admin Credentials will be used to join the Root CA Server to the domain
        as well as configre the new Root CA. This means that the Domain Account provided to this parameter MUST be a member
        of the following Security Groups in Active Directory:
            - Domain Admins
            - Domain Users
            - Enterprise Admins
            - Group Policy Creator Owners
            - Schema Admins

    .PARAMETER PSRemotingCredentials
        This parameter is MANDATORY.

        This parameter takes a PSCredential.

        The credential provided to this parameter should correspond to a User Account that has permission to
        remote into the target Windows Server. If you're using a Vagrant Box (which is what will be deployed
        if you use the -CreateNewVMs switch), then the value for this parameter should be created via:

            $VagrantVMPassword = ConvertTo-SecureString 'vagrant' -AsPlainText -Force
            $VagrantVMAdminCreds = [pscredential]::new("vagrant",$VagrantVMPassword)

    .PARAMETER IPOfServerToBeRootCA
        This parameter is OPTIONAL, however, if you do NOT use the -CreateNewVMs parameter, this parameter becomes MANDATORY.

        This parameter takes a string that represents an IPv4 Address referring to an EXISTING Windows Server on the network
        that will become the new Root CA.

    .PARAMETER IPofDomainController
        This parameter is OPTIONAL, however, if you cannot resolve the Domain Name provided to the -ExistingDomain parameter
        from the localhost, then this parameter becomes MANDATORY.

        This parameter takes a string that represents an IPv4 address referring to a Domain Controller (not readonly) on the
        domain specified by the -ExistingDomain parameter.

    .PARAMETER PrimaryHyperVHostIPOverride
        This parameter is OPTIONAL.

        This parameter takes a string that represents an IPv4 Address that you would like to use as your External Netowrk on your
        Hyper-V host.

    .PARAMETER SkipHyperVInstallCheck
        This parameter is OPTIONAL.

        This parameter is a switch. If used, this function will not check to make sure Hyper-V is installed on the localhost.

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -

        PS C:\Users\zeroadmin> $VagrantVMPassword = ConvertTo-SecureString 'vagrant' -AsPlainText -Force
        PS C:\Users\zeroadmin> $VagrantVMAdminCreds = [pscredential]::new("vagrant",$VagrantVMPassword)
        PS C:\Users\zeroadmin> $DomainAdminCreds = [pscredential]::new("alpha\alphaadmin",$(Read-Host 'Enter Passsword' -AsSecureString))
        Enter Passsword: ************
        PS C:\Users\zeroadmin> $CreateRootCASplatParams = @{
        >> CreateNewVMs                            = $True
        >> VMStorageDirectory                      = "H:\VirtualMachines"
        >> ExistingDomain                          = "alpha.lab"
        >> IPOfDomainController                    = "192..168.2.112"
        >> PSRemotingCredentials                   = $VagrantVMAdminCreds
        >> DomainAdminCredentials                  = $DomainAdminCreds
        >> }
        PS C:\Users\zeroadmin> $CreateRootCAResult = Create-RootCA @CreateRootCASplatParams

#>
function Create-RootCA {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$False)]
        [switch]$CreateNewVMs,

        [Parameter(Mandatory=$False)]
        [string]$VMStorageDirectory,

        [Parameter(Mandatory=$False)]
        [string]$Windows2016VagrantBox = "jborean93/WindowsServer2016", # Alternate - StefanScherer/windows_2016

        [Parameter(Mandatory=$True)]
        [ValidatePattern("^([a-z0-9]+(-[a-z0-9]+)*\.)+([a-z]){2,}$")]
        [string]$ExistingDomain,

        [Parameter(Mandatory=$True)]
        [pscredential]$DomainAdminCredentials,

        [Parameter(Mandatory=$True)]
        [pscredential]$PSRemotingCredentials,

        [Parameter(Mandatory=$False)]
        [string]$IPofServerToBeRootCA,

        [Parameter(Mandatory=$False)]
        [string]$IPofDomainController,

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
    # New-RootCA

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

    if ($PSBoundParameters['CreateNewVMs']-and !$PSBoundParameters['VMStorageDirectory']) {
        $VMStorageDirectory = Read-Host -Prompt "Please enter the full path to the directory where all VM files will be stored"
    }

    if (!$PSBoundParameters['CreateNewVMs'] -and $PSBoundParameters['VMStorageDirectory']) {
        $CreateNewVMs = $True
    }

    if ($CreateNewVMs -and $PSBoundParameters['IPofServerToBeRootCA']) {
        $ErrMsg = "The parameter-IPofServerToBeRootCA, and was used in conjunction with parameters " +
        "that indicate that a new VM should be deployed (i.e. -CreateNewVMs and/or -VMStorageDirectory) " +
        "Please only use -IPofServerToBeRootCA if that server are already exists on the network. Halting!"
        Write-Error $ErrMsg
        $global:FunctionResult = "1"
        return
    }

    if (!$CreateNewVMs -and ! $PSBoundParameters['IPofServerToBeRootCA']) {
        Write-Error "The $($MyInvocation.MyCommand.Name) function requires either the -CreateNewVMs or -IPOfServerToBeRootCA parameter! Halting!"
        $global:FunctionResult = "1"
        return
    }

    <#
    if ($PSBoundParameters['IPofServerToBeRootCA']) {
        # Make sure we can reach RemoteHost IP(s) via WinRM/WSMan
        if (![bool]$(Test-Connection -Protocol WSMan -ComputerName $IPofServerToBeRootCA -Count 1 -ErrorAction SilentlyContinue)) {
            Write-Error "Unable to reach '$IPofServerToBeRootCA' via WinRM/WSMan! Halting!"
            $global:FunctionResult = "1"
            return
        }
    }
    #>

    if (!$PSBoundParameters['IPofDomainController']) {
        # Make sure we can Resolve the Domain/Domain Controller
        try {
            [array]$ResolveDomain = Resolve-DNSName -Name $ExistingDomain -ErrorAction Stop
            $IPofDomainController = $ResolveDomain[0].IPAddress
        }
        catch {
            Write-Error $_
            $global:FunctionResult = "1"
            return
        }
    }
    if (!$(TestIsValidIPAddress -IPAddress $IPofDomainController)) {
        Write-Error "'$IPOfDomainController' is NOT a valid IPv4 address! Halting!"
        $global:FunctionResult = "1"
        return
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

        # Make sure we have at least 35GB of Storage and 6GB of READILY AVAILABLE Memory
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
        
        if ($([Math]::Round($VMStorageDirectoryDriveInfo.FreeSpace / 1MB)-2000) -lt 35000) {
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
        if ($MemoryAvailableInGB -lt 6 -and !$ForceWithLowMemory) {
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

        $NewVMDeploySB = {
            $DeployBoxSplatParams = @{
                VagrantBox                  = $Windows2016VagrantBox
                CPUs                        = 2
                Memory                      = 4096
                VagrantProvider             = "hyperv"
                VMName                      = $DomainShortName + 'RootCA'
                VMDestinationDirectory      = $VMStorageDirectory
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

        if (!$IPofServerToBeRootCA) {
            $DomainShortName = $($ExistingDomain -split "\.")[0]

            Write-Host "Deploying New Root CA VM '$DomainShortName`RootCA'..."
            
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
                Wait            = $True
            }
            $NewRootCAVMDeployResult = New-Runspace @NewRootCAVMDeployJobSplatParams

            $IPofServerToBeRootCA = $NewRootCAVMDeployResult.VMIPAddress

            while (![bool]$(Get-VM -Name "$DomainShortName`RootCA" -ErrorAction SilentlyContinue)) {
                Write-Host "Waiting for $DomainShortName`RootCA VM to be deployed..."
                Start-Sleep -Seconds 15
            }

            if (!$IPofServerToBeRootCA) {
                $IPofServerToBeDomainController = $(Get-VMNetworkAdapter -VMName "$DomainShortName`RootCA").IPAddresses | Where-Object {TestIsValidIPAddress -IPAddress $_}
            }
        }

        [System.Collections.ArrayList]$VMsNotReportingIP = @()
        if (!$(TestIsValidIPAddress -IPAddress $IPofServerToBeRootCA)) {
            $null = $VMsNotReportingIP.Add("$DomainShortName`RootCA")
        }

        if ($VMsNotReportingIP.Count -gt 0) {
            Write-Error "The following VMs did NOT report thier IP Addresses within 30 minutes:`n$($VMsNotReportingIP -join "`n")`nHalting!"
            $global:FunctionResult = "1"
            return
        }

        # Make sure IP is a valid IPv4 address
        if (![bool]$(TestIsValidIPAddress -IPAddress $IPofServerToBeRootCA)) {
            Write-Error "'$IPofServerToBeRootCA' is NOT a valid IPv4 IP Address! Halting!"
            $global:FunctionResult = "1"
            return
        }

        Write-Host "Finished Deploying New VMs..."

        #endregion >> Deploy New VMs
    }

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
            Write-Error "Problem with Enable-PSRemoting WinRM Quick Config! Halting!"
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
    )

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
                Write-Error "Unable to create new PSSession to '$PSSessionName' using account '$($PSRemotingCredentials.UserName)'! Halting!"
                $global:FunctionResult = "1"
                return
            }
        }
        $Counter++
    }

    # Clear the PSSessions
    Get-PSSession | Remove-PSSession

    if ($CreateNewVMs) {
        $EndVMDeployment = Get-Date
        $TotalTime = $EndVMDeployment - $StartVMDeployment
        Write-Host "VM Deployment took $($TotalTime.Hours) hours and $($TotalTime.Minutes) minutes..." -ForegroundColor Yellow
    }

    #endregion >> Make Sure WinRM/WSMan Is Ready on the Remote Hosts


    #region >> Join the Servers to Domain And Rename If Necessary

    # Check if DC and RootCA should be the same server. If not, then need to join RootCA to Domain.
    if ($IPofDomainController -ne $IPofServerToBeRootCA) {
        $JoinDomainRSJobSB = {
            $JoinDomainSBAsString = @(
                '# Synchronize time with time servers'
                '$null = W32tm /resync /rediscover /nowait'
                ''
                '# Make sure the DNS Client points to IP of Domain Controller (and others from DHCP)'
                '$PrimaryIfIndex = $(Get-CimInstance Win32_IP4RouteTable | Where-Object {'
                '    $_.Destination -eq "0.0.0.0" -and $_.Mask -eq "0.0.0.0"'
                '} | Sort-Object Metric1)[0].InterfaceIndex'
                '$NicInfo = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object {$_.InterfaceIndex -eq $PrimaryIfIndex}'
                '$PrimaryIP = $NicInfo.IPAddress | Where-Object {TestIsValidIPAddress -IPAddress $_}'
                '$CurrentDNSServerListInfo = Get-DnsClientServerAddress -InterfaceIndex $PrimaryIfIndex -AddressFamily IPv4'
                '$CurrentDNSServerList = $CurrentDNSServerListInfo.ServerAddresses'
                '$UpdatedDNSServerList = [System.Collections.ArrayList][array]$CurrentDNSServerList'
                '$UpdatedDNSServerList.Insert(0,$args[0])'
                '$null = Set-DnsClientServerAddress -InterfaceIndex $PrimaryIfIndex -ServerAddresses $UpdatedDNSServerList'
                ''
                '$CurrentDNSSuffixSearchOrder = $(Get-DNSClientGlobalSetting).SuffixSearchList'
                '[System.Collections.ArrayList]$UpdatedDNSSuffixList = $CurrentDNSSuffixSearchOrder'
                '$UpdatedDNSSuffixList.Insert(0,$args[2])'
                'Set-DnsClientGlobalSetting -SuffixSearchList $UpdatedDNSSuffixList'
                ''
                '# Try resolving the Domain for 30 minutes'
                '$Counter = 0'
                'while (![bool]$(Resolve-DNSName $args[2] -ErrorAction SilentlyContinue) -and $Counter -le 120) {'
                '    Write-Host "Waiting for DNS to resolve Domain Controller..."'
                '    Start-Sleep -Seconds 15'
                '    $Counter++'
                '}'
                'if (![bool]$(Resolve-DNSName $args[2] -ErrorAction SilentlyContinue)) {'
                '    Write-Error "Unable to resolve Domain $($args[2])! Halting!"'
                '    $global:FunctionResult = "1"'
                '    return'
                '}'
                ''
                '# Join Domain'
                'Rename-Computer -NewName $args[1]'
                'Start-Sleep -Seconds 10'
                'Add-Computer -DomainName $args[2] -Credential $args[3] -Options JoinWithNewName,AccountCreate -Force -Restart'
            )
            
            try {
                $JoinDomainSB = [scriptblock]::Create($($JoinDomainSBAsString -join "`n"))
            }
            catch {
                Write-Error "Problem creating `$JoinDomainSB! Halting!"
                $global:FunctionResult = "1"
                return
            }
    
            $InvCmdJoinDomainSplatParams = @{
                ComputerName    = $IPofServerToBeRootCA
                Credential      = $PSRemotingCredentials
                ScriptBlock     = $JoinDomainSB
                ArgumentList    = $IPofDomainController,$DesiredHostNameRootCA,$ExistingDomain,$DomainAdminCredentials
            }
            try {
                Invoke-Command @InvCmdJoinDomainSplatParams
            }
            catch {
                Write-Error $_
                $global:FunctionResult = "1"
                return
            }
        }

        # Check if RootCA is already part of $ExistingDomain/$NewDomain
        $InvCmdRootCADomainSplatParams = @{
            ComputerName        = $IPofServerToBeRootCA
            Credential          = $PSRemotingCredentials
            ScriptBlock         = {$(Get-CimInstance win32_computersystem).Domain}
            ErrorAction         = "Stop"
        }
        try {
            $RootCADomain = Invoke-Command @InvCmdRootCADomainSplatParams
        }
        catch {
            Write-Error $_
            $global:FunctionResult = "1"
            return
        }

        if ($RootCADomain -ne $ExistingDomain) {
            Write-Host "Joining the Root CA to the Domain..."
            $DesiredHostNameRootCA = $DomainShortName + "RootCA"

            $RunspaceNames = $($global:RSSyncHash.Keys | Where-Object {$_ -match "Result$"}) | foreach {$_ -replace 'Result',''}
            $JoinRootCAJobName = NewUniqueString -PossibleNewUniqueString "JoinRootCA" -ArrayOfStrings $RunspaceNames

            <#
            $JoinRootCAArgList = @(
                $IPofServerToBeRootCA
                $PSRemotingCredentials
                $IPofDomainController
                $DesiredHostNameRootCA
                $ExistingDomain
                $DomainAdminCredentials
            )
            #>
            $JoinRootCAJobSplatParams = @{
                RunspaceName    = $JoinRootCAJobName
                Scriptblock     = $JoinDomainRSJobSB
                Wait            = $True
            }
            $JoinRootCAResult = New-Runspace @JoinRootCAJobSplatParams

            # Verify Root CA is Joined to Domain
            # Try to create a PSSession to the Root CA for 15 minutes, then give up
            Write-Host "Trying to remote into RootCA at '$IPofServerToBeRootCA' with Domain Admin Credentials after Joining Domain..."
            $PSSessionName = NewUniqueString -ArrayOfStrings $(Get-PSSession).Name -PossibleNewUniqueString "ToRootCAPostDomainJoin"
            $Counter = 0
            while (![bool]$(Get-PSSession -Name $PSSessionName -ErrorAction SilentlyContinue)) {
                try {
                    $RootCAPSSessionPostDomainJoin = New-PSSession -ComputerName $IPofServerToBeRootCA -Credential $DomainAdminCredentials -Name $PSSessionName -ErrorAction SilentlyContinue
                    if (![bool]$(Get-PSSession -Name $PSSessionName -ErrorAction SilentlyContinue)) {throw}
                }
                catch {
                    if ($Counter -le 60) {
                        Write-Warning "New-PSSession '$PSSessionName' failed. Trying again in 15 seconds..."
                        Start-Sleep -Seconds 15
                    }
                    else {
                        Write-Error "Unable to create new PSSession to '$PSSessionName' using account '$($DomainAdminCredentials.UserName)'! Halting!"
                        $global:FunctionResult = "1"
                        return
                    }
                }
                $Counter++
            }

            if (!$RootCAPSSessionPostDomainJoin) {
                Write-Error "Unable to create a PSSession to the Root CA Server at '$IPofServerToBeRootCA' using Domain Admin Credentials $($DomainAdminCredentials.UserName)! Halting!"
                $global:FunctionResult = "1"
                return
            }

            # Make sure there is a Reverse DNS PTR record for $IPofServerToBeRootCA
            if (!$DesiredHostNameRootCA) {
                try {
                    $RootCANetworkInfo = ResolveHost -HostNameOrIP $IPofServerToBeRootCA
                    $RootCAHostName = $RootCANetworkInfo.HostName
                }
                catch {
                    Write-Error $_
                    $global:FunctionResult = "1"
                    return
                }
            }
            else {
                $RootCAHostName = $DesiredHostNameRootCA
            }

            $RootCAPTRRecordFQDN = $RootCAHostName + '.' + $FinalDomainName
            $ThisModuleFunctionsStringArray = $(Get-Module MiniLab).Invoke({$FunctionsForSBUse})
            try {
                $UpdateDNSPTRPSSession = New-PSSession -ComputerName $IPofDomainController -Credential $DomainAdminCredentials

                $UpdatePTRResult = Invoke-Command -Session $UpdateDNSPTRPSSession -ScriptBlock {
                    $PTRRecords = Get-DnsServerResourceRecord -ZoneName $using:FinalDomainName -RRType A
                    $PTRecordIPs = $PTRRecords.RecordData.IPv4Address.IPAddressToString | Sort-Object | Get-Unique

                    if ($PTRecordIPs -notcontains $using:IPOfServerToBeRootCA) {
                        $using:ThisModuleFunctionsStringArray | Where-Object {$_ -ne $null} | foreach {Invoke-Expression $_ -ErrorAction SilentlyContinue}    

                        $PrimaryIfIndex = $(Get-CimInstance Win32_IP4RouteTable | Where-Object {
                            $_.Destination -eq '0.0.0.0' -and $_.Mask -eq '0.0.0.0'
                        } | Sort-Object Metric1)[0].InterfaceIndex
                        $NicInfo = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object {$_.InterfaceIndex -eq $PrimaryIfIndex}
                        $PrimaryIP = $NicInfo.IPAddress | Where-Object {TestIsValidIPAddress -IPAddress $_}
                        $Prefix = $(Get-NetIPAddress -IPAddress $PrimaryIP).PrefixLength

                        $ip = [ipaddress]$PrimaryIP
                        $MaskString = $(ConvertSubnetMask -CIDR $Prefix).Mask
                        $mask = [ipaddress]$MaskString
                        $netid = ([ipaddress]($ip.Address -band $mask.Address)).IPAddressToString
                        $binary = [convert]::ToString($mask.Address, 2)
                        $mask_length = ($binary -replace 0,$null).Length
                        $NetworkAndSubnetMaskCidr = '{0}/{1}' -f $netid, $mask_length
                        $NetIdOctetArray = $netid -split '\.'
                        $ZoneNameCheck = $NetIdOctetArray[2] + '.' + $NetIdOctetArray[1] + '.' + $NetIdOctetArray[0] + '.' + 'in-addr.arpa'

                        Add-DnsServerResourceRecord -Name $using:RootCAHostName -Ptr -ZoneName $ZoneNameCheck -AllowUpdateAny -PtrDomainName $using:RootCAPTRRecordFQDN
                    }
                }
            }
            catch {
                Write-Error $_
                $global:FunctionResult = "1"
                return
            }
        }
    }

    #endregion >> Join the Servers to Domain And Rename If Necessary


    #region >> Create the Root CA

    # Remove All Existing PSSessions
    Get-PSSession | Remove-PSSession

    Write-Host "Creating the New Root CA..."
    $NewRootCAResult = New-RootCA -DomainAdminCredentials $DomainAdminCredentials -RootCAIPOrFQDN $IPofServerToBeRootCA -ExpectedDomain $FinalDomainName

    #endregion >> Create the Root CA

    $EndTime = Get-Date
    $TotalAllOpsTime = $EndTime - $StartTime
    Write-Host "All operations for the $($MyInvocation.MyCommand.Name) function took $($TotalAllOpsTime.Hours) hours and $($TotalAllOpsTime.Minutes) minutes" -ForegroundColor Yellow

    $NewRootCAResult

}

# SIG # Begin signature block
# MIIMaAYJKoZIhvcNAQcCoIIMWTCCDFUCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUUd1IwXxoKr6hB5BTqsnsncaT
# UOGgggndMIIEJjCCAw6gAwIBAgITawAAADqEP46TDmc/hQAAAAAAOjANBgkqhkiG
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
# BDEWBBRyOuRq3bUrjGo505unJYzcIKDbmjANBgkqhkiG9w0BAQEFAASCAQAeDT4s
# Ltml2CnwVXozh/cYhIqUGxnNupr8g4wS1NPCiaTsAJZ6PzOe4f/82cODcwN0INTG
# YNObL5Zk3S2A+34lje+9GgPpDI/Elt0171o3NfNkROQINYgHF9B9ZEAlZzu4CQk5
# u8GNndxhBgmPgKhZ2nh9Ycw/2DGSYMTrJVVfd6J4JtJn5+Z7rDGnpggOI4pY5Y0Z
# 7jqP1sDA8as+PkHMZmVyCWIqZzxIQsY85RmT9A6SeM8NGPPD3HwE1QffltJigOfq
# aAFYfYZqX8bKPPt+dtG/ZVNxZpFxOu73PWbNgkfFyDViovC9MgIKt9tenZDduhhU
# Qm3qKEQaNDF0kfIC
# SIG # End signature block
