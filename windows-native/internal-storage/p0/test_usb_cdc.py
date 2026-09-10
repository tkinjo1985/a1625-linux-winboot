"""Execute the actual CDC request and receive-completion C bodies with MMIO mocks."""
from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parents[3]
source = (ROOT / 'third_party/HoolockLinux-m1n1-p0/src/usb_dwc2.c').read_text()
def function(signature):
    start = source.index(signature + '\n{')
    return source[start:source.index('\n}', start) + 2]

prefix = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <stddef.h>
typedef uint8_t u8; typedef uint32_t u32;
#define CDC_ACM_PIPE_MAX 2
#define USB_REQUEST_CDC_GET_LINE_CODING 0x21
#define USB_REQUEST_CDC_SET_LINE_CODING 0x20
#define USB_REQUEST_CDC_SET_CTRL_LINE_STATE 0x22
#define USB_LEP_CTRL_OUT 0
#define USB_LEP_CTRL_IN 1
#define USB_LEP_CDC_BULK_OUT 2
#define USB_LEP_CDC_BULK_OUT_2 5
#define DWC2_DOEPTSIZ(n) (n)
#define BIT(n) (1U<<(n))
#define DWC2_DAINT 10
#define DWC2_DOEPINT(n) (20+(n))
#define DWC2_DIEPINT(n) (30+(n))
#define DWC2_DOEPCTL(n) (40+(n))
#define DWC2_DOEPINT_XFER_COMPL BIT(0)
#define DWC2_DOEPINT_SETUP BIT(3)
#define DWC2_DOEPINT_STUP_PKT_RCVD BIT(15)
#define min(a,b) ((a)<(b)?(a):(b))
#define usb_debug_printf(...) ((void)0)
#define usb_error_printf(...) ((void)0)
union usb_setup_packet {struct {u8 bmRequestType,bRequest;uint16_t wValue,wIndex,wLength;} raw;};
'''
prefix += source[source.index('enum ep0_state {'):source.index('};', source.index('enum ep0_state {'))+2]
prefix += r'''
typedef struct {
 unsigned regs; enum ep0_state ep0_state;
 void *ep0_read_buffer; unsigned ep0_read_buffer_len;
 const void *ep0_buffer; unsigned ep0_buffer_len;
 struct {void *xfer_buffer;} endpoints[2];
 struct {bool ready;u8 cdc_line_coding[7];} pipe[2];
} dwc2_dev_t;
static unsigned stalls,bulk,statuses,setups,remaining,daint,outint,inint,armed;
static void usb_dwc2_ep_set_stall(dwc2_dev_t*d,int e,int s){(void)d;(void)e;stalls+=s;}
static void usb_dwc2_cdc_start_bulk_out_xfer(dwc2_dev_t*d,int e){(void)d;(void)e;bulk++;}
static void usb_dwc2_start_status_phase(dwc2_dev_t*d,int e){(void)d;(void)e;statuses++;}
static void usb_dwc2_start_setup_phase(dwc2_dev_t*d){(void)d;setups++;}
static void usb_dwc2_ep0_handle_setup(dwc2_dev_t*d);
static int usb_dwc2_ep0_start_data_send_phase(dwc2_dev_t*d){(void)d;return 0;}
static int usb_dwc2_ep0_start_data_recv_phase(dwc2_dev_t*d){assert(d->ep0_read_buffer_len==7);armed++;return 0;}
static void dma_rmb(void){}
static unsigned read32(unsigned a){if(a==10)return daint;if(a==20)return outint;if(a==30)return inint;return remaining;}
static void write32(unsigned a,unsigned v){(void)a;(void)v;}
'''
body = function('static void usb_dwc2_ep0_handle_class(dwc2_dev_t *dev, const union usb_setup_packet *setup)') if 'static void usb_dwc2_ep0_handle_class(dwc2_dev_t *dev, const union usb_setup_packet *setup)\n{' in source else ''
assert body
body += '\nstatic void usb_dwc2_ep0_handle_setup(dwc2_dev_t*d){usb_dwc2_ep0_handle_class(d,d->endpoints[0].xfer_buffer);}\n'
body += function('static void usb_dwc2_ep0_handle_xfer_done(dwc2_dev_t *dev)')
body += function('static void usb_dwc2_ep0_handle_xfer_not_ready(dwc2_dev_t *dev)')
ep = function('static void usb_dwc2_handle_interrupts_ep(dwc2_dev_t *dev)')
# The full EP0 part, excluding unrelated bulk endpoint mocks.
body += ep[:ep.index('    if (daint & BIT(16 + 2))')] + '\n}\n'
main = r'''
int main(void){
 dwc2_dev_t d={0};u8 payload[7]={0,0xc2,1,0,0,0,8};d.endpoints[0].xfer_buffer=payload;
 union usb_setup_packet s={.raw={0x21,0x20,0,0,7}};
 for(unsigned p=0;p<2;p++){
  s.raw.wIndex=p*2;usb_dwc2_ep0_handle_class(&d,&s);
  assert(d.ep0_state==USB_DWC2_EP0_STATE_DATA_RECV);
  assert(!memcmp(d.pipe[p].cdc_line_coding,"\0\0\0\0\0\0\0",7));
  d.ep0_state=USB_DWC2_EP0_STATE_DATA_RECV_DONE;remaining=0;
  usb_dwc2_ep0_handle_xfer_done(&d);
  assert(!memcmp(d.pipe[p].cdc_line_coding,payload,7));
  assert(d.ep0_state==USB_DWC2_EP0_STATE_DATA_SEND_STATUS && !d.ep0_read_buffer);
  d.ep0_state=USB_DWC2_EP0_STATE_DATA_SEND_STATUS_DONE;
  usb_dwc2_ep0_handle_xfer_done(&d);assert(d.ep0_state==USB_DWC2_EP0_STATE_SETUP_HANDLE);
  s.raw.bmRequestType=0xa1;s.raw.bRequest=0x21;
  usb_dwc2_ep0_handle_class(&d,&s);assert(d.ep0_buffer_len==7 && d.ep0_buffer==d.pipe[p].cdc_line_coding);
  s.raw.bmRequestType=0x21;s.raw.bRequest=0x20;
 }
 for(unsigned n=0;n<64;n++)if(n!=7){s.raw.wLength=n;unsigned before=stalls;usb_dwc2_ep0_handle_class(&d,&s);assert(stalls==before+1);}
 s.raw.wLength=7;
 for(unsigned req=0;req<256;req++)if(req!=0x21){s.raw.bmRequestType=req;unsigned before=stalls;usb_dwc2_ep0_handle_class(&d,&s);assert(stalls==before+1);}
 s.raw.bmRequestType=0x21;s.raw.wValue=1;
 {unsigned before=stalls;usb_dwc2_ep0_handle_class(&d,&s);assert(stalls==before+1);}
 s.raw.wValue=0;
 for(unsigned idx=0;idx<6;idx++)if(idx!=0 && idx!=2){s.raw.wIndex=idx;unsigned before=stalls;usb_dwc2_ep0_handle_class(&d,&s);assert(stalls==before+1);}
 s.raw.wIndex=0;
 for(unsigned n=1;n<=7;n++){
  usb_dwc2_ep0_handle_class(&d,&s);d.ep0_state=USB_DWC2_EP0_STATE_DATA_RECV_DONE;
  remaining=n;unsigned before=stalls;payload[0]=99;usb_dwc2_ep0_handle_xfer_done(&d);
  assert(stalls==before+1 && d.pipe[0].cdc_line_coding[0]==0 && !d.ep0_read_buffer);
 }
 s.raw.bRequest=0x22;s.raw.wLength=0;s.raw.wValue=1;
 usb_dwc2_ep0_handle_class(&d,&s);usb_dwc2_ep0_handle_class(&d,&s);
 assert(bulk==1 && statuses==2 && d.pipe[0].ready);
 s.raw.wValue=0;usb_dwc2_ep0_handle_class(&d,&s);assert(!d.pipe[0].ready);
 // New SETUP interrupts an unfinished OUT; simultaneous old IN must not advance it.
 s.raw.bRequest=0x20;s.raw.wLength=7;s.raw.wValue=0;
 d.endpoints[0].xfer_buffer=&s;d.ep0_read_buffer=d.pipe[1].cdc_line_coding;
 d.ep0_read_buffer_len=7;d.ep0_state=USB_DWC2_EP0_STATE_DATA_RECV_DONE;
 daint=BIT(16)|BIT(0);outint=DWC2_DOEPINT_STUP_PKT_RCVD;inint=1;
 usb_dwc2_handle_interrupts_ep(&d);
 assert(d.ep0_state==USB_DWC2_EP0_STATE_SETUP_PENDING && !d.ep0_read_buffer);
 outint=DWC2_DOEPINT_SETUP|DWC2_DOEPINT_XFER_COMPL;
 usb_dwc2_handle_interrupts_ep(&d);
 assert(d.ep0_state==USB_DWC2_EP0_STATE_DATA_RECV_DONE && armed==1);
 d.endpoints[0].xfer_buffer=payload;remaining=0;daint=BIT(16);outint=1;
 usb_dwc2_handle_interrupts_ep(&d);
 assert(d.ep0_state==USB_DWC2_EP0_STATE_DATA_SEND_STATUS_DONE);
 daint=BIT(0);inint=1;usb_dwc2_handle_interrupts_ep(&d);
 assert(d.ep0_state==USB_DWC2_EP0_STATE_SETUP_HANDLE);
 return 0;
}
'''
out = ROOT / 'artifacts/p0-usb/tests'
out.mkdir(parents=True, exist_ok=True)
(out / 'cdc.c').write_text(prefix + body + main)
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
subprocess.run([str(gcc), '-std=c11', str(out/'cdc.c'), '-o', str(out/'cdc.exe')], check=True)
subprocess.run([str(out/'cdc.exe')], check=True)
print('Actual CDC handler/receive bodies: valid pipes, short OUT, lengths, interfaces, GET and DTR passed')
