#include <libusb-1.0/libusb.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    libusb_context *context = NULL;
    libusb_device **devices = NULL;
    libusb_device_handle *handle = NULL;
    ssize_t count;
    int matches = 0;
    int result = 1;

    if (libusb_init(&context) != LIBUSB_SUCCESS)
        return 2;
    count = libusb_get_device_list(context, &devices);
    if (count < 0)
        goto out;

    for (ssize_t i = 0; i < count; i++) {
        struct libusb_device_descriptor descriptor;
        if (libusb_get_device_descriptor(devices[i], &descriptor) != LIBUSB_SUCCESS)
            continue;
        if (descriptor.idVendor != 0x05ac || descriptor.idProduct != 0x1227)
            continue;
        matches++;
        if (matches == 1 && libusb_open(devices[i], &handle) != LIBUSB_SUCCESS)
            handle = NULL;
    }
    if (matches != 1 || handle == NULL) {
        fprintf(stderr, "Expected exactly one openable 05ac:1227 DFU device; found %d\n", matches);
        goto out;
    }

    /* One standard control-IN read only: no configuration, claim, reset or OUT request. */
    uint8_t bytes[18] = {0};
    int transferred = libusb_control_transfer(handle, 0x80, LIBUSB_REQUEST_GET_DESCRIPTOR,
                                               LIBUSB_DT_DEVICE << 8, 0, bytes,
                                               sizeof(bytes), 500);
    printf("DFU_READONLY_DESCRIPTOR requested=18 returned=%d timeout_ms=500\n", transferred);
    if (transferred != (int)sizeof(bytes))
        goto out;
    if (bytes[0] != sizeof(bytes) || bytes[1] != LIBUSB_DT_DEVICE ||
        bytes[8] != 0xac || bytes[9] != 0x05 || bytes[10] != 0x27 || bytes[11] != 0x12) {
        fprintf(stderr, "Unexpected DFU device descriptor\n");
        goto out;
    }
    result = 0;

out:
    if (handle != NULL)
        libusb_close(handle);
    if (devices != NULL)
        libusb_free_device_list(devices, 1);
    libusb_exit(context);
    return result;
}
