#Notes
    #Created: August 2021

    #Required PS Modules:
        #PowerCLI
    
    #Script goals:
        #Deploy VMware server via PowerCLI.
            #Specify things such as IP, Network, Servername, Datastore. All options within VMwares customization process.
        #When system comes online:
            #Rename local admin account, and set a password.
            #Disable guest account.
            #Create associated RDP and Admin AD groups.
            #Disable non-essential Windows services.
                #Print Spooler
                #XBOX services.
                #AllJoyn Router Service
                #Bluetooth Support Service
                #WAP Push Messaging Routing Service
                #Internet Connection Sharing
                #Phone Service
                #Printer Extenstions and Notifications
                #Radio Management Service
            #Place computer account in appropiate AD groups and OUs.
        #Like to haves
            #IISCRYPTO.

#Variables
    $VCenterServer = "vcenter.domain.com"
    $Environments = "PROD","DEV"
    $BusinessDivisions = "Corporate","DevOPS","IT"
    $BackupTypes = "2 Week Retention","4 Week Retention","No Backups"
    $ServerFunctions = "Application","Web","Database","File","Management"
    $DMZDomain = "domain.dmz"
    $InternalDomain = "domain.net"
    $DMZDNS = Resolve-DnsName -Type NS -Name $DMZDomain
    $InternalDNS = Resolve-DnsName -Type NS -Name $InternalDomain    
    $IPPattern = "^([1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])(\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){3}$"
    $CurrentDate = Get-Date -Format d

#Functions
    #Quick function to give the user a prompt of specific options.
        function Get-UserPrompt {
            param (
                [Parameter(Mandatory=$true)]
                [string[]]$Options,
                [Parameter(Mandatory=$true)]
                [string]$Prompt        
            )
            
            [int]$Response = 0;
            [bool]$ValidResponse = $false    

            while (!($ValidResponse)) {            
                [int]$OptionNo = 0

                Write-Host $Prompt -ForegroundColor DarkYellow
                Write-Host "[0]: Cancel"

                foreach ($Option in $Options) {
                    $OptionNo += 1
                    Write-Host ("[$OptionNo]: {0}" -f $Option)
                }

                if ([Int]::TryParse((Read-Host), [ref]$Response)) {
                    if ($Response -eq 0) {
                        return ''
                    }
                    elseif($Response -le $OptionNo) {
                        $ValidResponse = $true
                    }
                }
            }

            return $Options.Get($Response - 1)
        }
    
    #Quick function to request specified information.
        Function Get-DeploymentVariables{
            param(
                [Parameter(Mandatory=$true)]
                [string]$Prompt
                )
            Write-Host $Prompt -ForegroundColor DarkYellow
            Read-Host
        }
    
    #Pull correct folder by specifying the path. Copied directly from: https://www.lucd.info/2012/05/18/folder-by-path/
        function Get-FolderByPath{
            <#
            .SYNOPSIS Retrieve folders by giving a path
            .DESCRIPTION The function will retrieve a folder by it's path.
            The path can contain any type of leave (folder or datacenter).
            .NOTES
            Author: Luc Dekens .PARAMETER Path The path to the folder. This is a required parameter.
            .PARAMETER
            Path The path to the folder. This is a required parameter.
            .PARAMETER
            Separator The character that is used to separate the leaves in the path. The default is '/'
            .EXAMPLE
            PS> Get-FolderByPath -Path "Folder1/Datacenter/Folder2"
            .EXAMPLE
            PS> Get-FolderByPath -Path "Folder1>Folder2" -Separator '>'
            #>
            
            param(
            [CmdletBinding()]
            [parameter(Mandatory = $true)]
            [System.String[]]${Path},
            [char]${Separator} = '/'
            )
            
            process{
                if((Get-PowerCLIConfiguration).DefaultVIServerMode -eq "Multiple"){
                $vcs = $global:defaultVIServers
                }
                else{
                $vcs = $global:defaultVIServers[0]
                }
                $folders = @()
            
                foreach($vc in $vcs){
                $si = Get-View ServiceInstance -Server $vc
                $rootName = (Get-View -Id $si.Content.RootFolder -Property Name).Name
                foreach($strPath in $Path){
                    $root = Get-Folder -Name $rootName -Server $vc -ErrorAction SilentlyContinue
                    $strPath.Split($Separator) | ForEach-Object{
                    $root = Get-Inventory -Name $_ -Location $root -NoRecursion -Server $vc -ErrorAction SilentlyContinue
                    if((Get-Inventory -Location $root -NoRecursion | Select-Object -ExpandProperty Name) -contains "vm"){
                        $root = Get-Inventory -Name "vm" -Location $root -Server $vc -NoRecursion
                    }
                    }
                    $root | Where-Object {$_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.FolderImpl]}|ForEach-Object{
                    $folders += Get-Folder -Name $_.Name -Location $root.Parent -NoRecursion -Server $vc
                    }
                }
                }
                $folders
            }
            }

#Connect to VCenter Server. Will prompt for credentials.
    Connect-VIServer $VCenterServer

#Prompts for all variables.
    #PROD/DEV/QA/TEST.
        $ChosenEnvironment = Get-UserPrompt -Options $Environments -Prompt "Choose Environment."
        if($ChosenEnvironment -eq "PROD"){
            $ChosenHost = Get-VMHost -Location "Datacenter Production" | Sort-Object MemoryUsageGB -Descending | Select-Object -Last 1
            $FolderPathStart = "Datacenter Production/"
            $ChosenCluster = Get-Cluster -Name "Datacenter Production"
        }
        if($ChosenEnvironment -eq "DEV"){
            $ChosenHost = Get-VMHost -Location "Datacenter Development" | Sort-Object MemoryUsageGB -Descending | Select-Object -Last 1
            $FolderPathStart = "Datacenter Development/"
            $ChosenCluster = "Datacenter Development"
            $ChosenCluster = Get-Cluster -Name "Datacenter Development"
        }

    #Business Division
        $ChosenDivision = Get-UserPrompt -Options $BusinessDivisions -Prompt "Choose Business Division."

    #VM Notes
        $ChosenNotes = Get-DeploymentVariables -Prompt "Enter VM Notes"

    #Server Owner
        $ChosenOwner = Get-DeploymentVariables -Prompt "Enter Server Owner"

    #Server Function
        $ChosenFunction = Get-UserPrompt -Options $ServerFunctions -Prompt "Choose Server Function"

    #Creator
        $ChosenCreator = Get-DeploymentVariables -Prompt "Enter Your Name"

    #HD Event
        $ChosenHDEvent = Get-DeploymentVariables -Prompt "Enter HD Event Number"
    
    #Domain.
        $ChosenDomain = Get-UserPrompt -Options ("DMZ","Internal") -Prompt "Choose Domain."

    #OS.
        $ChosenOS = Get-UserPrompt -Options ("2016","2019") -Prompt "Choose OS."
        if($ChosenOS -eq "2019"){
            $ChosenTemplate = Get-Template -Name "SRV2019_Template"
        }
        if($ChosenOS -eq "2016"){
            $ChosenTemplate = Get-Template -Name "SRV2016_Template"
        }

    #Name.
        $ChosenName = Get-DeploymentVariables -Prompt "Enter Server Name"

    #Network. This may need to change when switching to distributed switches.
        $VMNetworks = Get-VirtualPortGroup | Sort-Object Name | Get-Unique
        $ChosenNetwork = Get-UserPrompt -Options $VMNetworks -Prompt "Choose Network."
        
        Do{
            $ChosenIP = Get-DeploymentVariables -Prompt "Enter IP Address." 
            $IPTest = $null
            $IPTest = Test-Connection $ChosenIP -ErrorAction Ignore
            $IPCheck = $ChosenIP -match $IPPattern
            if($IPCheck -eq $true){
                if($null -ne $IPTest){
                    Write-Host "IP is already in use. Try again." -ForegroundColor Red
                }}
            if($IPCheck -eq $false) {
                Write-Host "That's not a valid IP address. Try again." -ForegroundColor Red
            }
        }
        Until ($null -eq $IPTest -and $IPCheck -eq $true)

        Do{
            $ChosenMask = $null
            $ChosenMask = Get-DeploymentVariables -Prompt "Enter Subnet Mask."
            $MaskCheck = $ChosenMask -match $IPPattern
            If($MaskCheck -eq $false){
                Write-Host "That's not a valid Subnet Mask. Try again." -ForegroundColor Red
            }
        }
        Until ($MaskCheck -eq $true)
        
        Do{
            $ChosenGateway = $null
            $ChosenGateway = Get-DeploymentVariables -Prompt "Enter Gateway."
            $GatewayCheck = $ChosenGateway -match $IPPattern
            If($GatewayCheck -eq $false){
                Write-Host "That's not a valid Gateway. Try again." -ForegroundColor Red
            }
        }
        Until ($GatewayCheck -eq $true)

    #Backup type.
        $ChosenBackup = Get-UserPrompt -Options $BackupTypes -Prompt "Choose Backup Options"

    #Datastore.
        if($ChosenEnvironment -eq "DEV"){
            $Datastores = Get-DatastoreCluster -Location "Datacenter Development" | Select-Object Name   
            $ChosenDatastore = Get-UserPrompt -Options $Datastores.Name -Prompt "Choose Datastore"
        }
        if($ChosenEnvironment -eq "PROD"){
            $Datastores = Get-DatastoreCluster -Location "Datacenter Production" | Select-Object Name   
            $ChosenDatastore = Get-UserPrompt -Options $Datastores.Name -Prompt "Choose Datastore"
        }
    
    #Socket count.
        $ChosenSockets = Get-UserPrompt -Options ("2","4","6","8","10","12") -Prompt "Choose Number of Cores"

    #Core count.
        #$ChosenCores = Get-UserPrompt -Options ("1","2","3","4","5","6") -Prompt "Choose Number of Cores Per Socket"
        $ChosenCores = $ChosenSockets/2

    #Memory.
        $ChosenMemory = Get-UserPrompt -Options ("6","8","10","12","14","16") -Prompt "Choose Memory GB"

    #Update group.
        $ADUpdateGroup = Get-ADGroup -Filter {Name -Like "*WSUS*" -and Name -NotLike "WSUSUpdates"} | Sort-Object Name
        $ChosenUpdateGroup = Get-UserPrompt -Options $ADUpdateGroup.Name -Prompt "Choose Update Group"



#Script
    #Confirm chosen options are correct.
        $Title = "Confirmation"
        $Prompt = “You have chosen the following options:

        Environment - $ChosenEnvironment 
        Business Division - $ChosenDivision 
        Owner = $ChosenOwner
        Server Function - $ChosenFunction
        Notes - $ChosenNotes
        Creator - $ChosenCreator
        Helpdesk - $ChosenHDEvent
        Creation Date - $CurrentDate
        Domain - $ChosenDomain
        OS - $ChosenOS
        Name - $ChosenName
        VM Network - $ChosenNetwork 
        IP Address - $ChosenIP
        Subnet Mask - $ChosenMask
        Gateway - $ChosenGateway
        Backups - $ChosenBackup 
        Datastore - $ChosenDatastore
        Socket Count - $ChosenSockets
        Core Count Per Socket - $ChosenCores
        Memory - $ChosenMemory
        Update Group - $ChosenUpdateGroup
        `nAre you sure you want to continue?
        `nYou will need to manually undo any changes that happen after this point.”
        $Choices = [System.Management.Automation.Host.ChoiceDescription[]] @("Yes", "Cancel")
        $Default = 1
        $Choice = $host.UI.PromptForChoice($Title, $Prompt, $Choices, $Default)
        switch($Choice)
            {
                0 {Write-Host "Continuing." -ForegroundColor Green}
                1 {Write-Host "Cancelling." -ForegroundColor Red
                    Return}
            }
    
    #Deploy VM. Must program in wait for spin-up.
        #Select OS Customization Spec
            if($ChosenDomain -eq "DMZ"){
                $OSCustomization = Get-OSCustomizationSpec -Name "Server_2016/19_Template_DMZ"
                $ChosenDNS = $DMZDNS
            }
            if($ChosenDomain -eq "Internal"){
                $OSCustomization = Get-OSCustomizationSpec -Name "Server_2016/19_Template_NET"
                $ChosenDNS = $InternalDNS
            }
            Get-OSCustomizationSpec -Name Temp | Remove-OSCustomizationSpec -confirm:$false -ErrorAction Ignore | Out-Null
            Get-OSCustomizationSpec -Name $OSCustomization | New-OSCustomizationSpec -Name Temp -Type NonPersistent | Set-OSCustomizationSpec -NamingScheme vm | Out-Null
            Get-OSCustomizationSpec -Name Temp | Get-OSCustomizationNicMapping | Set-OSCustomizationNicMapping -IpMode UseStaticIP -IpAddress $ChosenIP -SubnetMask $ChosenMask -DefaultGateway $ChosenGateway -Dns $ChosenDNS.IP4Address | Out-Null
            $ChosenCustomization = Get-OSCustomizationSpec -Name Temp
        
        #Select VM Cluster   

        
        #Deploy VM
            if($BackupTypes -eq "No Backups"){
                $FolderName = $FolderPathStart+$ChosenBackup+"/"+$ChosenDivision
            }
            else {
                $FolderName = $FolderPathStart+"Backup/"+$ChosenBackup+"/"+$ChosenDivision
            }
            $ChosenFolder = Get-FolderByPath -Path  $FolderName
            New-VM -Name $ChosenName -Template $ChosenTemplate -OSCustomizationSpec $ChosenCustomization -Datastore $ChosenDatastore -Location $ChosenFolder -NetworkName $ChosenNetwork -VMHost $ChosenHost -ResourcePool $ChosenCluster | Out-Null
            Set-VM -VM $ChosenName -NumCpu $ChosenSockets -CoresPerSocket $ChosenCores -MemoryGB $ChosenMemory -Notes $ChosenNotes -Confirm:$false | Out-Null
            Set-Annotation -Entity $ChosenName -CustomAttribute "Environment" -Value $ChosenEnvironment | Out-Null
            Set-Annotation -Entity $ChosenName -CustomAttribute "Business Division" -Value $ChosenDivision| Out-Null
            Set-Annotation -Entity $ChosenName -CustomAttribute "Created Date" -Value $CurrentDate | Out-Null
            Set-Annotation -Entity $ChosenName -CustomAttribute "Creator" -Value $ChosenCreator | Out-Null
            Set-Annotation -Entity $ChosenName -CustomAttribute "Domain" -Value $ChosenDomain | Out-Null
            Set-Annotation -Entity $ChosenName -CustomAttribute "Owner" -Value $ChosenOwner | Out-Null
            Set-Annotation -Entity $ChosenName -CustomAttribute "Server Function" -Value $ChosenFunction | Out-Null
            Set-Annotation -Entity $ChosenName -CustomAttribute "HD Event" -Value $ChosenHDEvent | Out-Null
            Start-VM -VM $ChosenName | Out-Null
    
    #Ensure VM is ready to go.
        #Options:
            #Get-ADComputer returns a non-error. Requires unique name, which can be checked for and possibly deleted at beginning of script.
            #Time delay.
    #Modify Windows settings
    #Update VMTools
    #Update OS