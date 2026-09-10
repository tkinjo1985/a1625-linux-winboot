/* One synchronous descriptor request through the exact parent USB hub. */
#ifndef UNICODE
#define UNICODE
#endif
#define _UNICODE
#include <windows.h>
#include <cfgmgr32.h>
#include <usbioctl.h>
#include <stdio.h>
#include <stdlib.h>

static ULONGLONG now_ms(void) { return GetTickCount64(); }
static void phase(FILE *f, const char *p) {
    fprintf(f, "{\"tick_ms\":%llu,\"phase\":\"%s\"}\n", (unsigned long long)now_ms(), p); fflush(f);
}
static HANDLE open_hub(wchar_t *instance, FILE *log) {
    GUID hub={0xf18a0e88,0xc30c,0x11d0,{0x88,0x15,0x00,0xa0,0xc9,0x06,0xbe,0xd8}};
    ULONG count=0; CONFIGRET cr=CM_Get_Device_Interface_List_SizeW(&count,&hub,instance,CM_GET_DEVICE_INTERFACE_LIST_PRESENT);
    if(cr||count<2||count>32768){fprintf(log,"{\"tick_ms\":%llu,\"phase\":\"hub_interface_size_failed\",\"configret\":%lu,\"count\":%lu}\n",(unsigned long long)now_ms(),(unsigned long)cr,(unsigned long)count);return INVALID_HANDLE_VALUE;}
    wchar_t *paths=calloc(count,sizeof(wchar_t)); if(!paths){phase(log,"hub_path_allocation_failed");return INVALID_HANDLE_VALUE;}
    cr=CM_Get_Device_Interface_ListW(&hub,instance,paths,count,CM_GET_DEVICE_INTERFACE_LIST_PRESENT);
    if(cr||!paths[0]||paths[wcslen(paths)+1]){fprintf(log,"{\"tick_ms\":%llu,\"phase\":\"hub_interface_list_failed\",\"configret\":%lu}\n",(unsigned long long)now_ms(),(unsigned long)cr);free(paths);return INVALID_HANDLE_VALUE;}
    HANDLE h=CreateFileW(paths,GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,NULL,OPEN_EXISTING,0,NULL);
    DWORD e=h==INVALID_HANDLE_VALUE?GetLastError():ERROR_SUCCESS;free(paths);
    fprintf(log,"{\"tick_ms\":%llu,\"phase\":\"hub_open_returned\",\"ok\":%s,\"error\":%lu}\n",(unsigned long long)now_ms(),h==INVALID_HANDLE_VALUE?"false":"true",(unsigned long)e);return h;
}
int wmain(int argc,wchar_t **argv) {
    setvbuf(stdout,NULL,_IONBF,0);setvbuf(stderr,NULL,_IONBF,0);if(argc!=6)return 2;
    FILE *log=_wfopen(argv[4],L"wb");if(!log)return 2;setvbuf(log,NULL,_IONBF,0);phase(log,"helper_started");
    wchar_t *end;unsigned long port=wcstoul(argv[2],&end,10);BOOL product=wcscmp(argv[3],L"product")==0,p0e2=wcscmp(argv[3],L"p0e2")==0;
    if(*end||port<1||port>255||(!product&&!p0e2)){phase(log,"argument_failed");fclose(log);return 2;}
    HANDLE hub=open_hub(argv[1],log);if(hub==INVALID_HANDLE_VALUE){fclose(log);return 3;}
    unsigned char ib[4096]={0};USB_NODE_CONNECTION_INFORMATION_EX *info=(void*)ib;info->ConnectionIndex=port;DWORD returned=0;
    phase(log,"connection_info_entered");ULONGLONG start=now_ms();BOOL ok=DeviceIoControl(hub,IOCTL_USB_GET_NODE_CONNECTION_INFORMATION_EX,ib,sizeof(ib),ib,sizeof(ib),&returned,NULL);DWORD error=ok?0:GetLastError();
    fprintf(log,"{\"tick_ms\":%llu,\"phase\":\"connection_info_returned\",\"ok\":%s,\"returned\":%lu,\"elapsed_ms\":%llu,\"error\":%lu}\n",(unsigned long long)now_ms(),ok?"true":"false",(unsigned long)returned,(unsigned long long)(now_ms()-start),(unsigned long)error);
    if(!ok||returned<sizeof(*info)||info->ConnectionStatus!=DeviceConnected||info->DeviceDescriptor.idVendor!=0x1209||info->DeviceDescriptor.idProduct!=0x316d){phase(log,"connection_identity_failed");CloseHandle(hub);fclose(log);return 4;}
    enum{MAX_DESCRIPTOR=128};unsigned char rb[sizeof(USB_DESCRIPTOR_REQUEST)+MAX_DESCRIPTOR]={0};USB_DESCRIPTOR_REQUEST *r=(void*)rb;r->ConnectionIndex=port;r->SetupPacket.bmRequest=0x80;r->SetupPacket.bRequest=0x06;r->SetupPacket.wValue=(USB_STRING_DESCRIPTOR_TYPE<<8)|(product?2:4);r->SetupPacket.wIndex=0x0409;r->SetupPacket.wLength=product?MAX_DESCRIPTOR:46;
    fprintf(log,"{\"tick_ms\":%llu,\"phase\":\"descriptor_entered\",\"bmRequestType\":128,\"bRequest\":6,\"wValue\":%u,\"wIndex\":1033,\"wLength\":%u}\n",(unsigned long long)now_ms(),r->SetupPacket.wValue,r->SetupPacket.wLength);
    start=now_ms();returned=0;ok=DeviceIoControl(hub,IOCTL_USB_GET_DESCRIPTOR_FROM_NODE_CONNECTION,rb,sizeof(rb),rb,sizeof(rb),&returned,NULL);error=ok?0:GetLastError();
    fprintf(log,"{\"tick_ms\":%llu,\"phase\":\"descriptor_returned\",\"ok\":%s,\"returned\":%lu,\"elapsed_ms\":%llu,\"error\":%lu}\n",(unsigned long long)now_ms(),ok?"true":"false",(unsigned long)returned,(unsigned long long)(now_ms()-start),(unsigned long)error);CloseHandle(hub);if(!ok){fclose(log);return 5;}
    size_t raw_len=returned>sizeof(*r)?returned-sizeof(*r):0;FILE *raw=_wfopen(argv[5],L"wb");if(!raw){phase(log,"raw_open_failed");fclose(log);return 6;}fwrite(r->Data,1,raw_len,raw);fclose(raw);
    if(raw_len<2||r->Data[1]!=USB_STRING_DESCRIPTOR_TYPE||r->Data[0]<2||(r->Data[0]&1)||r->Data[0]!=raw_len){phase(log,"descriptor_malformed");fclose(log);return 6;}
    phase(log,"descriptor_valid_shape");printf("{\"api_ok\":true,\"returned\":%lu,\"raw_length\":%llu,\"descriptor_length\":%u,\"type\":%u,\"index\":%u}\n",(unsigned long)returned,(unsigned long long)raw_len,r->Data[0],r->Data[1],product?2:4);fclose(log);return 0;
}
