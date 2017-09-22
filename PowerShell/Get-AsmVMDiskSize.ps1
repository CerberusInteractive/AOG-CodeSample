<#
.SYNOPSIS
    This script grab all ASM VM VHD file in the subscription and caculate VHD size, leveraging the wazvhdsize tool developed by Sandrino Di Mattia (https://github.com/sandrinodimattia).
.DESCRIPTION
    This script grab all ASM VM VHD file in the subscription and caculate VHD size, leveraging the wazvhdsize tool developed by Sandrino Di Mattia (https://github.com/sandrinodimattia).
.Example
    .\Get-AsmVMDiskSize.ps1 -subscriptionid xxxxxxx-xxxx-xxxx-xxxxxxx
    Then input the username and password of Azure China.
#>

param(
    [Parameter(Mandatory = $true)]
    [String]$SubscriptionID
)

Function Count-VHDSize
{
    param(
        [Parameter(Mandatory = $true)]
        [String]$storageaccountname,

        [Parameter(Mandatory = $true)]
        [String]$storageaccountkey,

        [Parameter(Mandatory = $true)]
        [String]$VHDUri
    )

    $result = .\wazvhdsize.exe $storageaccountname $storageaccountkey $VHDUri
    $vhdlength = ('{0:n0}' -f (($result[6].split(" "))[5].trim("(") / 1GB)) -replace ","

    If ($result[7] -like " Error*") {
        return @{"vhdlength" = $vhdlength; "usedsize" = "The VHD file is currently occupied, cannot read usedsize."}
    } Else {
        $usedsize = ('{0:n2}' -f (($result[7].split(" "))[6].trim("(") / 1GB)) -replace ","
        return @{"vhdlength" = $vhdlength; "usedsize" = $usedsize}
    }
}

Import-Module Azure
Add-AzureAccount -Environment azurechinacloud
Get-AzureSubscription -SubscriptionId $SubscriptionID | Select-AzureSubscription

$armfile = $env:USERPROFILE+"\Downloads\wazvhdsize-v1.0\asmvms-"+$subscriptionID+".csv"
$wazvhdsizepath = $env:USERPROFILE+"\Downloads\wazvhdsize-v1.0"
Set-Content $asmfile -Value "CloudService,VMName,VMSize,DiskName,OSorData,VHDUri,StorageAccount,VHDLength,VHDUsedSize"
cd $wazvhdsizepath

Write-Host "ASM part started!"

$asmvms = Get-AzureVM

foreach($asmvm in $asmvms) {
    Start-Sleep -Seconds 20
    $vmcloudservice = $asmvm.ServiceName
    $vmname = $asmvm.Name
    $vmsize = $asmvm.InstanceSize
    $vmosdiskname = $asmvm.VM.OSVirtualHardDisk.DiskName
    $vmosdiskuri = $asmvm.VM.OSVirtualHardDisk.MediaLink.AbsoluteUri
    $vmosdiskstorageaccountname = ($asmvm.VM.OSVirtualHardDisk.MediaLink.Host.Split("."))[0]
    $vmosdiskstorageaccountkey = (Get-AzureStorageKey -StorageAccountName $vmosdiskstorageaccountname).Primary

    $osvhdsize = Count-VHDSize $vmosdiskstorageaccountname $vmosdiskstorageaccountkey $vmosdiskuri

    If ($vmsize -like "*DS*") {
        Add-Content $asmfile -Value ($vmcloudservice+","+$vmname+","+$vmsize+","+$vmosdiskname+",OSDisk,"+$vmosdiskuri+","+$vmosdiskstorageaccountname+","+$osvhdsize.vhdlength+",Premium Disks don't support GetBlobSize method")
    } else {
        Add-Content $asmfile -Value ($vmcloudservice+","+$vmname+","+$vmsize+","+$vmosdiskname+",OSDisk,"+$vmosdiskuri+","+$vmosdiskstorageaccountname+","+$osvhdsize.vhdlength+","+$osvhdsize.usedsize)
    }

    $datadisks = $asmvm.vm.DataVirtualHardDisks
    If ($datadisks.count -eq 0) {
        Write-Host ("The VM "+$vmname+" contains no data disk.")
    } else {
        Write-Host ("The VM "+$vmname+" contains "+$datadisks.count+" data disk(s).")
        foreach ($datadisk in $datadisks) {
            $vmdatadiskname = $datadisk.DiskName
            $vmdatadiskuri = $datadisk.MediaLink.AbsoluteUri
            $vmdatadiskstorageaccountname = ($datadisk.MediaLink.Host.Split("."))[0]
            $vmdatadiskstorageaccountkey = (Get-AzureStorageKey -StorageAccountName $vmdatadiskstorageaccountname).Primary

            $datavhdsize = Count-VHDSize $vmdatadiskstorageaccountname $vmdatadiskstorageaccountkey $vmdatadiskuri

            If ($vmsize -like "*DS*") {
                Add-Content $asmfile -Value ($vmcloudservice+","+$vmname+","+$vmsize+","+$vmdatadiskname+",DataDisk,"+$vmdatadiskuri+","+$vmdatadiskstorageaccountname+","+$datavhdsize.vhdlength+",Premium Disks don't support GetBlobSize method")
            } else {
                Add-Content $asmfile -Value ($vmcloudservice+","+$vmname+","+$vmsize+","+$vmdatadiskname+",DataDisk,"+$vmdatadiskuri+","+$vmdatadiskstorageaccountname+","+$datavhdsize.vhdlength+","+$datavhdsize.usedsize)
            }
        } 
    }
}

Write-Host "ASM part finished!"


