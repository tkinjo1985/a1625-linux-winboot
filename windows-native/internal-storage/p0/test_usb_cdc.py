"""Execute the actual CDC request and receive-completion C bodies with MMIO mocks."""
from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parents[3]
source = (ROOT / 'third_party/HoolockLinux-m1n1-p0/src/usb_dwc2.c').read_text()
usb_source = (ROOT / 'third_party/HoolockLinux-m1n1-p0/src/usb.c').read_text()
assert '#ifdef ANS1_P0\n    /* Windows binds this non-IAD dual-CDC device to management interface 2' in usb_source
assert 'usb_iodev->ops = &iodev_usb_dwc2_sec_ops;' in usb_source
assert '#else\n    usb_iodev->ops = &iodev_usb_dwc2_ops;' in usb_source
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
#define ANS1_P0 1
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
#define DWC2_DOEPDMA(n) (50+(n))
#define DWC2_DIEPDMA(n) (60+(n))
#define DWC2_DIEPTSIZ(n) (70+(n))
#define DWC2_DIEPCTL(n) (80+(n))
#define USB_LEP_CDC_BULK_IN_2 6
#define DWC2_DXEPCTLi_EnableEP (1U<<31)
#define DWC2_DXEPCTL_ClearNAK (1U<<26)
#define DWC2_DOEPINT_XFER_COMPL BIT(0)
#define DWC2_DOEPINT_SETUP BIT(3)
#define DWC2_DOEPINT_STUP_PKT_RCVD BIT(15)
#define min(a,b) ((a)<(b)?(a):(b))
#define usb_debug_printf(...) ((void)0)
#define usb_error_printf(...) ((void)0)
union usb_setup_packet {struct {u8 bmRequestType,bRequest;uint16_t wValue,wIndex,wLength;} raw;};
enum { P0_EP0_SETUP_CONSUMED=BIT(0),P0_EP0_GET_HANDLER=BIT(1),P0_EP0_IN_ARMED=BIT(2),
       P0_EP0_IN_COMPLETE=BIT(3),P0_EP0_STATUS_ARMED=BIT(4),
       P0_EP0_STATUS_COMPLETE=BIT(5),P0_EP0_NEXT_SETUP=BIT(6) };
#define P0_EP0_ARMED BIT(1)
#define P0_EP0_FROZEN BIT(2)
#define P0_EP0_MARK(dev,bit) do{if(((dev)->p0_ep0_flags&(P0_EP0_ARMED|P0_EP0_FROZEN))==P0_EP0_ARMED)(dev)->p0_ep0_trace|=(bit);}while(0)
static bool p0_is_get_line_coding(const union usb_setup_packet*s){return s->raw.bmRequestType==0xa1&&s->raw.bRequest==0x21&&s->raw.wValue==0&&s->raw.wIndex==2&&s->raw.wLength==7;}
'''
prefix += source[source.index('enum ep0_state {'):source.index('};', source.index('enum ep0_state {'))+2]
prefix += r'''
typedef struct {
 unsigned regs; enum ep0_state ep0_state;
 void *ep0_read_buffer; unsigned ep0_read_buffer_len;
 const void *ep0_buffer; unsigned ep0_buffer_len;
 bool ep0_ignore_next_in_completion;
 struct {void *xfer_buffer;unsigned in_flight;} endpoints[2];
 struct {bool ready;u8 cdc_line_coding[7];} pipe[2];
 u8 p0_ep0_trace;u8 p0_ep0_flags;bool p0_get_line_coding_active;
} dwc2_dev_t;
static void usb_dwc2_ep_hw_send(dwc2_dev_t*,u8,u32,u32);
static void usb_dwc2_ep_hw_recv(dwc2_dev_t*,u8,u32,u32);
static unsigned stalls,bulk,statuses,setups,remaining,daint,outint,inint,armed,dma_addr,dma_size,in_control_bits;
static void usb_dwc2_ep_set_stall(dwc2_dev_t*d,int e,int s){(void)d;(void)e;stalls+=s;}
static void usb_dwc2_cdc_start_bulk_out_xfer(dwc2_dev_t*d,int e){(void)d;(void)e;bulk++;}
static void usb_dwc2_start_status_phase(dwc2_dev_t*d,int e){statuses++;if(e==USB_LEP_CTRL_OUT)usb_dwc2_ep_hw_recv(d,e,64,1);}
static void usb_dwc2_start_setup_phase(dwc2_dev_t*d){(void)d;setups++;}
static void usb_dwc2_ep0_handle_setup(dwc2_dev_t*d);
static int usb_dwc2_ep0_start_data_recv_phase(dwc2_dev_t*d){assert(d->ep0_read_buffer_len==7);armed++;return 0;}
static void dma_rmb(void){}
static bool published;
static void dma_wmb(void){published=true;}
static unsigned read32(unsigned a){if(a==10)return daint;if(a==20)return outint;if(a==30)return inint;return remaining;}
static void write32(unsigned a,unsigned v){if(a==60){assert(published);dma_addr=v;}if(a==70)dma_size=v;}
static unsigned control_bits;
static void set32(unsigned a,unsigned v){if(a==80)in_control_bits=v;else control_bits=v;}
static const u8 phyEndpoints[]={0,0x80};
'''
body = function('static void usb_dwc2_ep0_handle_class(dwc2_dev_t *dev, const union usb_setup_packet *setup)') if 'static void usb_dwc2_ep0_handle_class(dwc2_dev_t *dev, const union usb_setup_packet *setup)\n{' in source else ''
assert body
body += function('static int usb_dwc2_ep0_start_data_send_phase(dwc2_dev_t *dev)')
body += '\nstatic void usb_dwc2_ep0_handle_setup(dwc2_dev_t*d){usb_dwc2_ep0_handle_class(d,d->endpoints[0].xfer_buffer);}\n'
body += function('static void usb_dwc2_ep0_handle_xfer_done(dwc2_dev_t *dev)')
body += function('static void usb_dwc2_ep0_handle_xfer_not_ready(dwc2_dev_t *dev)')
ep = function('static void usb_dwc2_handle_interrupts_ep(dwc2_dev_t *dev)')
# The full EP0 part, excluding unrelated bulk endpoint mocks.
body += ep[:ep.index('    if (daint & BIT(16 + 2))')] + '\n}\n'
reset = function('static void usb_dwc2_handle_usbrst(dwc2_dev_t *dev)')
# Execute the real software-state reset prefix; this does not model endpoint
# abort waits or reset-register side effects in the remainder of this function.
body += 'static const u8 cdc_default_line_coding[]={0x80,0x25,0,0,0,0,8};\n'
body += reset[:reset.index('    // usb_debug_printf("handle_usbrst:')] + '\n}\n'
body += function('static void usb_dwc2_ep_hw_recv(dwc2_dev_t *dev, u8 ep, u32 hw_xfer_size, u32 packet_count)')
body += function('static void usb_dwc2_ep_hw_send(dwc2_dev_t *dev, u8 ep, u32 hw_xfer_size, u32 packet_count)')
main = r'''
int main(void){
 dwc2_dev_t d={0};u8 payload[7]={0,0xc2,1,0,0,0,8};u8 in_payload[64]={0};
 d.endpoints[0].xfer_buffer=payload;d.endpoints[1].xfer_buffer=in_payload;
 union usb_setup_packet s={.raw={0x21,0x20,0,0,7}};
 // Exact driver-init sequence with a known synthetic line-coding value.
 dwc2_dev_t seqd={0};seqd.endpoints[0].xfer_buffer=payload;seqd.endpoints[1].xfer_buffer=in_payload;
 union usb_setup_packet seq={.raw={0xa1,0x21,0,2,7}};
 usb_dwc2_ep0_handle_class(&seqd,&seq);
 assert(seqd.ep0_buffer==seqd.pipe[1].cdc_line_coding && seqd.ep0_buffer_len==7);
 seq.raw.bmRequestType=0x21;seq.raw.bRequest=0x22;seq.raw.wLength=0;
 usb_dwc2_ep0_handle_class(&seqd,&seq);assert(!seqd.pipe[1].ready);
 seq.raw.bRequest=0x20;seq.raw.wLength=7;
 usb_dwc2_ep0_handle_class(&seqd,&seq);
 seqd.endpoints[0].xfer_buffer=payload;seqd.ep0_state=USB_DWC2_EP0_STATE_DATA_RECV_DONE;remaining=0;
 usb_dwc2_ep0_handle_xfer_done(&seqd);
 assert(!memcmp(seqd.pipe[1].cdc_line_coding,payload,7));
 seq.raw.bmRequestType=0xa1;seq.raw.bRequest=0x21;
 usb_dwc2_ep0_handle_class(&seqd,&seq);
 assert(seqd.ep0_buffer_len==7 && !memcmp(seqd.ep0_buffer,payload,7));
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
 unsigned bulk_before=bulk,statuses_before=statuses;
 usb_dwc2_ep0_handle_class(&d,&s);usb_dwc2_ep0_handle_class(&d,&s);
 assert(bulk==bulk_before+1 && statuses==statuses_before+2 && d.pipe[0].ready);
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
 // The next SETUP can be observed after DAINT was sampled but before the
 // preceding IN-status completion is serviced. That old completion must not
 // be interpreted as completion of the newly armed GET data phase.
 s.raw.bmRequestType=0xa1;s.raw.bRequest=0x21;s.raw.wValue=0;
 s.raw.wIndex=2;s.raw.wLength=7;d.endpoints[0].xfer_buffer=&s;
 d.ep0_state=USB_DWC2_EP0_STATE_DATA_SEND_STATUS_DONE;
 daint=BIT(16);outint=DWC2_DOEPINT_SETUP;inint=0;
 usb_dwc2_handle_interrupts_ep(&d);
 assert(d.ep0_state==USB_DWC2_EP0_STATE_DATA_SEND_DONE);
 daint=BIT(0);inint=DWC2_DOEPINT_XFER_COMPL;
 usb_dwc2_handle_interrupts_ep(&d);
 assert(d.ep0_state==USB_DWC2_EP0_STATE_DATA_SEND_DONE);
 // A following completion belongs to the newly armed GET and may advance it.
 usb_dwc2_handle_interrupts_ep(&d);
 assert(d.ep0_state==USB_DWC2_EP0_STATE_DATA_RECV_STATUS_DONE);
 // Reset while a line-coding OUT is pending discards its destination and DTR.
 d.ep0_read_buffer=d.pipe[1].cdc_line_coding;d.ep0_read_buffer_len=7;
 d.ep0_state=USB_DWC2_EP0_STATE_DATA_RECV_DONE;
 d.pipe[0].ready=d.pipe[1].ready=true;
 usb_dwc2_handle_usbrst(&d);
 assert(!d.ep0_read_buffer && !d.ep0_read_buffer_len);
 assert(d.ep0_state==USB_DWC2_EP0_STATE_IDLE);
 for(unsigned p=0;p<2;p++){
  assert(!d.pipe[p].ready);
  assert(!memcmp(d.pipe[p].cdc_line_coding,cdc_default_line_coding,7));
 }
 d.ep0_state=USB_DWC2_EP0_STATE_DATA_RECV_STATUS;
 usb_dwc2_ep_hw_recv(&d,0,64,1);
 assert(control_bits==(DWC2_DXEPCTLi_EnableEP|DWC2_DXEPCTL_ClearNAK));
 d.ep0_state=USB_DWC2_EP0_STATE_DATA_RECV;
 usb_dwc2_ep_hw_recv(&d,0,7,1);
 assert(control_bits==(DWC2_DXEPCTLi_EnableEP|DWC2_DXEPCTL_ClearNAK));
 // The observed A1/21 interface-2 request: IN data, OUT status, next SETUP.
 d.p0_ep0_trace=0;d.p0_ep0_flags=P0_EP0_ARMED;d.p0_get_line_coding_active=false;
 s.raw.bmRequestType=0xa1;s.raw.bRequest=0x21;s.raw.wValue=0;
 s.raw.wIndex=2;s.raw.wLength=7;d.endpoints[0].xfer_buffer=&s;
 daint=BIT(16);outint=DWC2_DOEPINT_SETUP;
 published=false;
 usb_dwc2_handle_interrupts_ep(&d);
 assert(d.ep0_state==USB_DWC2_EP0_STATE_DATA_SEND_DONE);
 assert(d.p0_ep0_trace==(P0_EP0_SETUP_CONSUMED|P0_EP0_GET_HANDLER|P0_EP0_IN_ARMED));
 assert(d.ep0_buffer==d.pipe[1].cdc_line_coding && d.ep0_buffer_len==7);
 assert(published && !memcmp(in_payload,d.pipe[1].cdc_line_coding,7));
 assert(dma_addr && dma_size==(1U<<19|7));
 assert(in_control_bits==(DWC2_DXEPCTLi_EnableEP|DWC2_DXEPCTL_ClearNAK));
 daint=BIT(0);inint=1;usb_dwc2_handle_interrupts_ep(&d);
 assert(d.ep0_state==USB_DWC2_EP0_STATE_DATA_RECV_STATUS_DONE);
 assert(d.p0_ep0_trace==(P0_EP0_SETUP_CONSUMED|P0_EP0_GET_HANDLER|P0_EP0_IN_ARMED|P0_EP0_IN_COMPLETE|P0_EP0_STATUS_ARMED));
 daint=BIT(16);outint=1;usb_dwc2_handle_interrupts_ep(&d);
 assert(d.ep0_state==USB_DWC2_EP0_STATE_SETUP_HANDLE);
 assert(d.p0_ep0_trace==0x3f && d.p0_get_line_coding_active);
 s.raw.bmRequestType=0;s.raw.bRequest=0;s.raw.wIndex=0;s.raw.wLength=0;
 daint=BIT(16);outint=DWC2_DOEPINT_SETUP;usb_dwc2_handle_interrupts_ep(&d);
 assert(d.p0_ep0_trace==0x7f && !d.p0_get_line_coding_active);
 return 0;
}
'''
main=main.replace(' return 0;', ' published=false;usb_dwc2_ep_hw_send(&d,1,7,1);assert(published && d.endpoints[1].in_flight==7);\n return 0;')
out = ROOT / 'artifacts/p0-usb/tests'
out.mkdir(parents=True, exist_ok=True)
(out / 'cdc.c').write_text(prefix + body + main)
gcc = Path.home() / 'scoop/apps/msys2/current/ucrt64/bin/gcc.exe'
os.environ['PATH'] = str(gcc.parent) + os.pathsep + os.environ['PATH']
subprocess.run([str(gcc), '-std=c11', str(out/'cdc.c'), '-o', str(out/'cdc.exe')], check=True)
subprocess.run([str(out/'cdc.exe')], check=True)
print('CDC request/completion, P0 pipe-1 binding, EP0 interleaving and software reset tests passed; hardware timing unverified')
