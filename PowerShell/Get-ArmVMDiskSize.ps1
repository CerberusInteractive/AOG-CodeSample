<#
.SYNOPSIS
    This script grab all ARM VM VHD file in the subscription and caculate VHD size, leveraging the wazvhdsize tool developed by Sandrino Di Mattia (https://github.com/sandrinodimattia).
.DESCRIPTION
    This script grab all ARM VM VHD file in the subscription and caculate VHD size, leveraging the wazvhdsize tool developed by Sandrino Di Mattia (https://github.com/sandrinodimattia).
.Example
    .\Get-ArmVMDiskSize.ps1 -subscriptionid xxxxxxx-xxxx-xxxx-xxxxxxx
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

Import-Module AzureRM
$PSversion = (Get-Module -Name AzureRM).Version.Major
If((Get-Module -Name AzureRM).Version.Major -lt 4){
    Write-Host "PowerShell Version too low! Please upgrade AzureRM module to 4.2.1 at least!";
    Exit
}
Login-AzureRmAccount -Environment azurechinacloud 
Get-AzureRmSubscription -SubscriptionId $SubscriptionID | Select-AzureRmSubscription

$armfile = $env:USERPROFILE+"\Downloads\wazvhdsize-v1.0\armvms-"+$subscriptionID+".csv"
$wazvhdsizepath = $env:USERPROFILE+"\Downloads\wazvhdsize-v1.0"
Set-Content $armfile -Value "ResourceGroup,VMName,VMSize,DiskName,OSorData,VHDUri,StorageAccount,VHDLength,VHDUsedSize"
cd $wazvhdsizepath

Write-Host "ARM part starts!"

$armvms = Get-AzureRmVM

foreach($armvm in $armvms) {
    $vmresourcegroup = $armvm.ResourceGroupName
    $vmname = $armvm.Name
    $vmsize = $armvm.HardwareProfile.VmSize
    $vmosdiskname = $armvm.StorageProfile.OsDisk.Name
    $vmosdiskuri = $armvm.StorageProfile.OsDisk.Vhd.Uri
    If ($vmosdiskuri -eq $null) {
        Write-Host ("The VM "+$vmname+" is using Managed Disks.")
        $vmosdisksize = (Get-AzureRmDisk -ResourceGroupName $vmresourcegroup -DiskName $vmosdiskname).DiskSizeGB
        Add-Content $armfile -Value ($vmresourcegroup+","+$vmname+","+$vmsize+“,”+$vmosdiskname+",OSDisk,No visible VHD files for Managed Disk VM,No visible storage account for Managed Disk VM,"+$vmosdisksize+",Managed Disks don't support GetBlobSize method")
        $datadisks = $armvm.StorageProfile.DataDisks
        If ($datadisks.Count -eq 0) {
            Write-Host ("The VM "+$vmname+" contains no data disk.")
        } else {
            Write-Host ("The VM "+$vmname+" contains "+$datadisks.Count+" data disk(s).")
            foreach ($datadisk in $datadisks) {
                $vmdatadiskname = $datadisk.Name
                $vmdatadisksize = (Get-AzureRmDisk -ResourceGroupName $vmresourcegroup -DiskName $vmdatadiskname).DiskSizeGB
                Add-Content $armfile -Value ($vmresourcegroup+","+$vmname+","+$vmsize+","+$vmdatadiskname+",DataDisk,No visible VHD files for Managed Disk VM,No visible storage account for Managed Disk VM,"+$vmdatadisksize+",Managed Disks don't support GetBlobSize method")
            }
        }
    } else {
        $vmosdiskstorageaccountname = ($armvm.StorageProfile.OsDisk.Vhd.Uri.Split("{/,.}"))[2]
        $vmosdiskstorageaccountkey = (Get-AzureRmStorageAccount | ? {$_.StorageAccountName -eq $vmosdiskstorageaccountname} | Get-AzureRmStorageAccountKey)[0].Value

        $osvhdsize = Count-VHDSize $vmosdiskstorageaccountname $vmosdiskstorageaccountkey $vmosdiskuri

        If ($vmsize -like "*DS*") {
            Add-Content $armfile -Value ($vmresourcegroup+","+$vmname+","+$vmsize+","+$vmosdiskname+",OSDisk,"+$vmosdiskuri+","+$vmosdiskstorageaccountname+","+$osvhdsize+",Premium Disks don't support GetBlobSize method")
        } else {
            Add-Content $armfile -Value ($vmresourcegroup+","+$vmname+","+$vmsize+","+$vmosdiskname+",OSDisk,"+$vmosdiskuri+","+$vmosdiskstorageaccountname+","+$osvhdsize.vhdlength+","+$osvhdsize.usedsize)
        }

        $datadisks = $armvm.StorageProfile.DataDisks
        If ($datadisks.count -eq 0) {
            Write-Host ("The VM "+$vmname+" contains no data disk.")
        } else {
            Write-Host ("The VM "+$vmname+" contains "+$datadisks.Count+" data disk(s).")
            foreach ($datadisk in $datadisks) {
                $vmdatadiskname = $datadisk.Name
                $vmdatadiskuri = $datadisk.Vhd.Uri
                $vmdatadiskstorageaccountname = ($vmdatadiskuri.Split("{/,.}"))[2]
                $vmdatadiskstorageaccountkey = (Get-AzureRmStorageAccount | ? {$_.StorageAccountName -eq $vmdatadiskstorageaccountname} | Get-AzureRmStorageAccountKey)[0].Value
                $datavhdsize = Count-VHDSize $vmdatadiskstorageaccountname $vmdatadiskstorageaccountkey $vmdatadiskuri
                
                If ($vmsize -like "*DS*") {
                    Add-Content $armfile -Value ($vmresourcegroup+","+$vmname+","+$vmsize+","+$vmdatadiskname+",DataDisk,"+$vmdatadiskuri+","+$vmdatadiskstorageaccountname+","+$datavhdsize.vhdlength+",Premium Disks don't support GetBlobSize method")
                } else {
                    Add-Content $armfile -Value ($vmresourcegroup+","+$vmname+","+$vmsize+","+$vmdatadiskname+",DataDisk,"+$vmdatadiskuri+","+$vmdatadiskstorageaccountname+","+$datavhdsize.vhdlength+","+$datavhdsize.usedsize)
                }
            }
        }
    }
}
Write-Host "ARM part finished!"


