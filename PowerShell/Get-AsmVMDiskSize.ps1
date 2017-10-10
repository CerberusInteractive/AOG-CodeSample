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

function Get-BlobBytes
{
    param (
        [Parameter(Mandatory=$true)]
        [Microsoft.WindowsAzure.Commands.Common.Storage.ResourceModel.AzureStorageBlob]$Blob)
 
    # Base + blob name
    $blobSizeInBytes = 124 + $Blob.Name.Length * 2
 
    # Get size of metadata
    $metadataEnumerator = $Blob.ICloudBlob.Metadata.GetEnumerator()
    while ($metadataEnumerator.MoveNext())
    {
        $blobSizeInBytes += 3 + $metadataEnumerator.Current.Key.Length + $metadataEnumerator.Current.Value.Length
    }
 
    if ($Blob.BlobType -eq [Microsoft.WindowsAzure.Storage.Blob.BlobType]::BlockBlob)
    {
        $blobSizeInBytes += 8
        $Blob.ICloudBlob.DownloadBlockList() | 
            ForEach-Object { $blobSizeInBytes += $_.Length + $_.Name.Length }
    }
    else
    {
        [int64]$rangeSize = 1GB
        [int64]$start = 0; $pages = "Start";
        
        While ($pages)
        {
            try
            {
                $pages = $Blob.ICloudBlob.GetPageRanges($start, $rangeSize)
            }
            catch
            {
                if ($_ -like "*the range specified is invalid*")
                {
                    $pages = $null
                    break
                }
                else
                {
                    write-error $_
                }
            }
            $pages | ForEach-Object { $blobSizeInBytes += 12 + $_.EndOffset - $_.StartOffset }
            $start += $rangeSize
        }
    }
    return @{"vhdlength" = "{0:F2}" -f ($blob.Length / 1GB) -replace ","; "usedsize" = "{0:F2}" -f ($blobSizeInBytes / 1GB) -replace ","}
} 

Import-Module Azure
#Add-AzureAccount -Environment azurechinacloud
Get-AzureSubscription -SubscriptionId $SubscriptionID 
Select-AzureSubscription -SubscriptionId $SubscriptionID

$asmfile = $env:USERPROFILE+"\Downloads\asmvms-"+$subscriptionID+".csv"
Set-Content $asmfile -Value "CloudService,VMName,VMSize,DiskName,OSorData,VHDUri,StorageAccount,VHDLength,VHDUsedSize"

Write-Host "ASM part started!"

$asmvms = Get-AzureVM

foreach($asmvm in $asmvms) 
{
    Start-Sleep -Seconds 20
    $vmcloudservice = $asmvm.ServiceName
    $vmname = $asmvm.Name
    $vmsize = $asmvm.InstanceSize
    $vmosdiskname = $asmvm.VM.OSVirtualHardDisk.DiskName
    $vmosdiskuri = $asmvm.VM.OSVirtualHardDisk.MediaLink.AbsoluteUri
    $vmosdiskstorageaccountname = ($asmvm.VM.OSVirtualHardDisk.MediaLink.Host.Split("."))[0]
    $vmosdiskstorageaccountkey = (Get-AzureStorageKey -StorageAccountName $vmosdiskstorageaccountname).Primary
    $vmosdiskstorageaccountcontext = New-AzureStorageContext -StorageAccountName $vmosdiskstorageaccountname -StorageAccountKey $vmosdiskstorageaccountkey
    $vmosdiskcontainername = ($vmosdiskuri.Split("/")[3])
    $vmosdiskblobname = ($vmosdiskuri.Split("/")[(($vmosdiskuri.Split("/")).count) - 1])
    $vmosdiskblob = Get-AzureStorageBlob -Context $vmosdiskstorageaccountcontext -blob $vmosdiskblobname -Container $vmosdiskcontainername

    $osvhdsize = Get-BlobBytes $vmosdiskblob

    If ($vmsize -like "*DS*") 
    {
        Add-Content $asmfile -Value ($vmcloudservice+","+$vmname+","+$vmsize+","+$vmosdiskname+",OSDisk,"+$vmosdiskuri+","+$vmosdiskstorageaccountname+","+$osvhdsize.vhdlength+",Premium Disks don't support GetBlobSize method")
    } 
    else 
    {
        Add-Content $asmfile -Value ($vmcloudservice+","+$vmname+","+$vmsize+","+$vmosdiskname+",OSDisk,"+$vmosdiskuri+","+$vmosdiskstorageaccountname+","+$osvhdsize.vhdlength+","+$osvhdsize.usedsize)
    }

    $datadisks = $asmvm.vm.DataVirtualHardDisks
    If ($datadisks.count -eq 0) 
    {
        Write-Host ("The VM "+$vmname+" contains no data disk.")
    } 
    else 
    {
        Write-Host ("The VM "+$vmname+" contains "+$datadisks.count+" data disk(s).")
        foreach ($datadisk in $datadisks) 
        {
            $vmdatadiskname = $datadisk.DiskName
            $vmdatadiskuri = $datadisk.MediaLink.AbsoluteUri
            $vmdatadiskstorageaccountname = ($datadisk.MediaLink.Host.Split("."))[0]
            $vmdatadiskstorageaccountkey = (Get-AzureStorageKey -StorageAccountName $vmdatadiskstorageaccountname).Primary
            $vmdatadiskstorageaccountcontext = New-AzureStorageContext -StorageAccountName $vmdatadiskstorageaccountname -StorageAccountKey $vmdatadiskstorageaccountkey
            $vmdatadiskcontainername = ($vmdatadiskuri.Split("/")[3])
            $vmdatadiskblobname = ($vmdatadiskuri.Split("/")[(($vmdatadiskuri.Split("/")).count) - 1])
            $vmdatadiskblob = Get-AzureStorageBlob -Context $vmdatadiskstorageaccountcontext -blob $vmdatadiskblobname -Container $vmdatadiskcontainername

            $datavhdsize = Get-BlobBytes $vmdatadiskblob

            If ($vmsize -like "*DS*") 
            {
                Add-Content $asmfile -Value ($vmcloudservice+","+$vmname+","+$vmsize+","+$vmdatadiskname+",DataDisk,"+$vmdatadiskuri+","+$vmdatadiskstorageaccountname+","+$datavhdsize.vhdlength+",Premium Disks don't support GetBlobSize method")
            } 
            else 
            {
                Add-Content $asmfile -Value ($vmcloudservice+","+$vmname+","+$vmsize+","+$vmdatadiskname+",DataDisk,"+$vmdatadiskuri+","+$vmdatadiskstorageaccountname+","+$datavhdsize.vhdlength+","+$datavhdsize.usedsize)
            }
        } 
    }
}

Write-Host "ASM part finished!"


