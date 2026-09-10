/* Read-only hub query. No COM open, control transfer, reset or proxy packet. */
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <cfgmgr32.h>
#include <usbioctl.h>
#include <stdio.h>
#include <stdlib.h>

int wmain(int argc, wchar_t **argv)
{
    if (argc != 3) return 2;
    wchar_t *end;
    unsigned long port = wcstoul(argv[2], &end, 10);
    if (*end || port < 1 || port > 255) return 2;
    GUID hub = {0xf18a0e88,0xc30c,0x11d0,{0x88,0x15,0x00,0xa0,0xc9,0x06,0xbe,0xd8}};
    ULONG count = 0;
    CONFIGRET cr = CM_Get_Device_Interface_List_SizeW(&count, &hub, argv[1], CM_GET_DEVICE_INTERFACE_LIST_PRESENT);
    if (cr || count < 2 || count > 32768) return 3;
    wchar_t *paths = calloc(count, sizeof(wchar_t));
    if (!paths) return 3;
    cr = CM_Get_Device_Interface_ListW(&hub, argv[1], paths, count, CM_GET_DEVICE_INTERFACE_LIST_PRESENT);
    if (cr || !paths[0] || paths[wcslen(paths)+1]) { free(paths); return 3; }
    HANDLE h = CreateFileW(paths, GENERIC_WRITE, FILE_SHARE_READ|FILE_SHARE_WRITE,
                           NULL, OPEN_EXISTING, 0, NULL);
    free(paths);
    if (h == INVALID_HANDLE_VALUE) { fprintf(stderr,"hub open error %lu\n",GetLastError()); return 4; }
    unsigned char buffer[4096] = {0};
    USB_NODE_CONNECTION_INFORMATION_EX *info = (void *)buffer;
    info->ConnectionIndex = port;
    DWORD returned = 0;
    BOOL ok = DeviceIoControl(h, IOCTL_USB_GET_NODE_CONNECTION_INFORMATION_EX,
                            buffer, sizeof(buffer), buffer, sizeof(buffer), &returned, NULL);
    DWORD error = GetLastError();
    CloseHandle(h);
    if (!ok) { fprintf(stderr,"hub query error %lu\n",error); return 5; }
    if (returned < sizeof(*info) || info->ConnectionStatus != DeviceConnected ||
        info->DeviceDescriptor.idVendor != 0x1209 || info->DeviceDescriptor.idProduct != 0x316d ||
        info->NumberOfOpenPipes > 32 ||
        sizeof(*info)+info->NumberOfOpenPipes*sizeof(USB_PIPE_INFO) > returned) return 6;
    printf("{\"vid\":%u,\"pid\":%u,\"device_class\":%u,\"device_subclass\":%u,"
           "\"configuration\":%u,\"open_pipes\":[",
           info->DeviceDescriptor.idVendor,info->DeviceDescriptor.idProduct,
           info->DeviceDescriptor.bDeviceClass,info->DeviceDescriptor.bDeviceSubClass,
           info->CurrentConfigurationValue);
    for (ULONG n=0;n<info->NumberOfOpenPipes;n++) {
        USB_ENDPOINT_DESCRIPTOR *ep = &info->PipeList[n].EndpointDescriptor;
        printf("%s{\"endpoint\":%u,\"attributes\":%u,\"max_packet\":%u}",
               n?",":"",ep->bEndpointAddress,ep->bmAttributes,ep->wMaxPacketSize);
    }
    puts("]}");
    return 0;
}
