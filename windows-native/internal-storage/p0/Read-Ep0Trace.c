/* One read-only EP0 string-descriptor request through the parent USB hub. */
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <cfgmgr32.h>
#include <usbioctl.h>
#include <stdio.h>
#include <stdlib.h>

static int hex_value(USHORT c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static int parse_hex(const USHORT *text, int count, unsigned long *value)
{
    *value = 0;
    for (int i = 0; i < count; i++) {
        int digit = hex_value(text[i]);
        if (digit < 0) return 0;
        *value = (*value << 4) | (unsigned long)digit;
    }
    return 1;
}

static HANDLE open_hub(wchar_t *instance)
{
    GUID hub = {0xf18a0e88,0xc30c,0x11d0,{0x88,0x15,0x00,0xa0,0xc9,0x06,0xbe,0xd8}};
    ULONG count = 0;
    if (CM_Get_Device_Interface_List_SizeW(&count, &hub, instance,
            CM_GET_DEVICE_INTERFACE_LIST_PRESENT) || count < 2 || count > 32768)
        return INVALID_HANDLE_VALUE;
    wchar_t *paths = calloc(count, sizeof(wchar_t));
    if (!paths)
        return INVALID_HANDLE_VALUE;
    if (CM_Get_Device_Interface_ListW(&hub, instance, paths, count,
            CM_GET_DEVICE_INTERFACE_LIST_PRESENT) || !paths[0] || paths[wcslen(paths) + 1]) {
        free(paths);
        return INVALID_HANDLE_VALUE;
    }
    HANDLE handle = CreateFileW(paths, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                NULL, OPEN_EXISTING, 0, NULL);
    free(paths);
    return handle;
}

int wmain(int argc, wchar_t **argv)
{
    if (argc != 3)
        return 2;
    wchar_t *end;
    unsigned long port = wcstoul(argv[2], &end, 10);
    if (*end || port < 1 || port > 255)
        return 2;
    HANDLE hub = open_hub(argv[1]);
    if (hub == INVALID_HANDLE_VALUE) {
        fprintf(stderr, "hub open error %lu\n", GetLastError());
        return 3;
    }

    unsigned char info_buffer[4096] = {0};
    USB_NODE_CONNECTION_INFORMATION_EX *info = (void *)info_buffer;
    info->ConnectionIndex = port;
    DWORD returned = 0;
    BOOL ok = DeviceIoControl(hub, IOCTL_USB_GET_NODE_CONNECTION_INFORMATION_EX,
                             info_buffer, sizeof(info_buffer), info_buffer, sizeof(info_buffer),
                             &returned, NULL);
    if (!ok || returned < sizeof(*info) || info->ConnectionStatus != DeviceConnected ||
        info->DeviceDescriptor.idVendor != 0x1209 || info->DeviceDescriptor.idProduct != 0x316d) {
        CloseHandle(hub);
        fprintf(stderr, "target identity gate failed\n");
        return 4;
    }

    unsigned char request_buffer[sizeof(USB_DESCRIPTOR_REQUEST) + 64] = {0};
    USB_DESCRIPTOR_REQUEST *request = (void *)request_buffer;
    request->ConnectionIndex = port;
    request->SetupPacket.bmRequest = 0x80;
    request->SetupPacket.bRequest = 0x06;
    request->SetupPacket.wValue = (USB_STRING_DESCRIPTOR_TYPE << 8) | 4;
    request->SetupPacket.wIndex = 0x0409;
    request->SetupPacket.wLength = 46;
    ok = DeviceIoControl(hub, IOCTL_USB_GET_DESCRIPTOR_FROM_NODE_CONNECTION,
                         request_buffer, sizeof(request_buffer), request_buffer,
                         sizeof(request_buffer), &returned, NULL);
    DWORD error = GetLastError();
    CloseHandle(hub);
    if (!ok) {
        fprintf(stderr, "descriptor request error %lu\n", error);
        return 5;
    }
    if (returned < sizeof(*request) + 46 || request->Data[0] != 46 ||
        request->Data[1] != USB_STRING_DESCRIPTOR_TYPE)
        return 6;
    const USHORT *text = (const USHORT *)(request->Data + 2);
    if (text[0] != 'P' || text[1] != '0' || text[2] != 'E' || text[3] != '2')
        return 7;
    unsigned long boot, generation, trace, flags, checksum;
    if (!parse_hex(text + 4, 8, &boot) || !parse_hex(text + 12, 4, &generation) ||
        !parse_hex(text + 16, 2, &trace) || !parse_hex(text + 18, 2, &flags) ||
        !parse_hex(text + 20, 2, &checksum))
        return 7;
    unsigned char expected = (unsigned char)boot ^ (unsigned char)(boot >> 8) ^
        (unsigned char)(boot >> 16) ^ (unsigned char)(boot >> 24) ^
        (unsigned char)generation ^ (unsigned char)(generation >> 8) ^
        (unsigned char)trace ^ (unsigned char)flags;
    if (checksum != expected) return 8;
    printf("{\"format\":\"P0E2\",\"boot_id\":%lu,\"generation\":%lu,"
           "\"trace\":%lu,\"flags\":%lu,\"checksum\":%lu}\n",
           boot, generation, trace, flags, checksum);
    return 0;
}
