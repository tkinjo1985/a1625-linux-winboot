param(
    [Parameter(Mandatory=$true)][string]$XmlPath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference='Stop'
$xmlFull=(Resolve-Path -LiteralPath $XmlPath).Path
if(Test-Path -LiteralPath $OutputPath){throw 'Analysis output already exists'}
[xml]$trace=Get-Content -LiteralPath $xmlFull -Raw
$events=@()
foreach($event in $trace.Events.Event){
    $complex=$event.EventData.ComplexData
    if(-not $complex -or $complex.Name -notmatch 'CONTROL_TRANSFER'){continue}
    $outer=@{}
    foreach($item in $event.EventData.Data){$outer[$item.Name]=[string]$item.'#text'}
    $fields=@{}
    foreach($item in $complex.Data){$fields[$item.Name]=[string]$item.'#text'}
    $events+=[pscustomobject][ordered]@{
        time=[string]$event.System.TimeCreated.SystemTime
        event_id=[int]$event.System.EventID
        opcode=[int]$event.System.Opcode
        device=$outer['fid_UsbDevice']
        pipe=$outer['fid_PipeHandle']
        irp=$outer['fid_IRP_Ptr']
        urb=$outer['fid_URB_Ptr']
        nt_status=$outer['fid_IRP_NtStatus']
        status=$fields['fid_URB_Hdr_Status']
        transfer_length=$fields['fid_URB_TransferBufferLength']
        bm_request_type=$fields['fid_URB_Setup_bmRequestType']
        request=$fields['fid_URB_Setup_bRequest']
        value=$fields['fid_URB_Setup_wValue']
        index=$fields['fid_URB_Setup_wIndex']
        length=$fields['fid_URB_Setup_wLength']
    }
}
$cdc=@($events | Where-Object {
    $_.index -in @('0x0','0x2') -and
    (($_.bm_request_type -eq '0xA1' -and $_.request -eq '0x21' -and $_.length -eq '0x7') -or
     ($_.bm_request_type -eq '0x21' -and $_.request -in @('0x20','0x22')))
})
$requests=@()
foreach($start in @($cdc | Where-Object opcode -eq 1)){
    $completions=@($events | Where-Object {
        $_.opcode -eq 2 -and $_.time -ge $start.time -and
        $_.device -eq $start.device -and $_.pipe -eq $start.pipe -and
        $_.irp -eq $start.irp -and $_.urb -eq $start.urb -and
        $_.bm_request_type -eq $start.bm_request_type -and $_.request -eq $start.request -and
        $_.value -eq $start.value -and $_.index -eq $start.index -and $_.length -eq $start.length
    } | Select-Object -First 1)
    $requests+=[pscustomobject][ordered]@{
        setup=$start
        completion_count=$completions.Count
        completions=$completions
    }
}
$result=[ordered]@{
    mode='P0-USB COM control trace analysis'
    source=$xmlFull
    source_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $xmlFull).Hash
    cdc_request_count=$requests.Count
    requests=$requests
    set_line_coding_count=@($requests | Where-Object {$_.setup.request -eq '0x20'}).Count
    nop_requests=0
    ans_requests=0
    nand_read_requests=0
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Output "Saved $($requests.Count) CDC request(s); no USB operation performed."
