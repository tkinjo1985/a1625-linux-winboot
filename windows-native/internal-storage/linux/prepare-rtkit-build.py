"""Prepare compile-only RTKit changes against the pinned baseline."""
from pathlib import Path
import difflib
import hashlib
import shutil

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
source = ROOT / 'artifacts/ans-baseline-kernel/drivers/soc/apple/rtkit.c'
raw = source.read_bytes()
if hashlib.sha256(raw).hexdigest() != 'ba3ce0750b5663e6b71ed5763745ea4a4df80fa6296bda4a538ff91ca26f43bb':
    raise ValueError('unexpected RTKit baseline')
original = raw.decode()
text = original


def replace(old, new):
    global text
    if text.count(old) != 1:
        raise ValueError('source anchor must occur exactly once')
    text = text.replace(old, new)


replace('#include "rtkit-internal.h"', '''#include "rtkit-internal.h"
#include <linux/delay.h>
#include <linux/ktime.h>''')
replace('''\tstruct apple_mbox_msg msg = {
\t\t.msg0 = message,''', '''\tktime_t deadline = ktime_add_ms(ktime_get(), 500);
\tint ret;
\tstruct apple_mbox_msg msg = {
\t\t.msg0 = message,''')
replace('\treturn apple_mbox_send(rtk->mbox, msg, atomic);', '''\tfor (;;) {
\t\tret = apple_mbox_send(rtk->mbox, msg, atomic);
\t\tif (ret != -EAGAIN || atomic)
\t\t\treturn ret;
\t\t/* EAGAIN guarantees no enqueue in the AKF backend. */
\t\tif (ktime_compare(ktime_get(), deadline) >= 0)
\t\t\treturn -ETIMEDOUT;
\t\tusleep_range(1000, 2000);
\t\tif (ktime_compare(ktime_get(), deadline) >= 0)
\t\t\treturn -ETIMEDOUT;
\t\tif (rtk->crashed)
\t\t\treturn -EIO;
\t}
'''.rstrip())
replace('''\tapple_rtkit_management_send(rtk, APPLE_RTKIT_MGMT_STARTEP, msg);

\treturn 0;''', '''\treturn apple_rtkit_management_send(rtk, APPLE_RTKIT_MGMT_STARTEP, msg);''')

replace('\tint i, ep;\n\tu64 reply;', '\tint i, ep, ret;\n\tu64 reply;')
replace('\tapple_rtkit_management_send(rtk, APPLE_RTKIT_MGMT_EPMAP_REPLY, reply);', '''\tret = apple_rtkit_management_send(rtk, APPLE_RTKIT_MGMT_EPMAP_REPLY, reply);
\tif (ret)
\t\tgoto abort_epmap;''')
replace('\t\t\tapple_rtkit_start_ep(rtk, ep);', '''\t\t\tret = apple_rtkit_start_ep(rtk, ep);
\t\t\tif (ret)
\t\t\t\tgoto abort_epmap;''')
replace('''\trtk->boot_result = 0;
\tcomplete_all(&rtk->epmap_completion);''', '''\trtk->boot_result = 0;
\tcomplete_all(&rtk->epmap_completion);
\treturn;

abort_epmap:
\trtk->boot_result = ret;
\tcomplete_all(&rtk->epmap_completion);''')

replace('\t/* The different size vs. IOVA shifts look odd but are indeed correct this way */', '''\t/* Preserve the only ownership record for a previously published buffer. */
\tif (buffer->size || buffer->buffer || buffer->iomem ||
\t    buffer->iova || buffer->is_mapped) {
\t\tdev_err(rtk->dev, "RTKit: duplicate buffer request on EP%02x\\n", ep);
\t\treturn -EBUSY;
\t}

\t/* The different size vs. IOVA shifts look odd but are indeed correct this way */''')
replace('\tif (buffer->iova && !rtk->ops->shmem_setup) {', '''\tif (!buffer->size) {
\t\terr = -EINVAL;
\t\tgoto error;
\t}

\tif (buffer->iova && !rtk->ops->shmem_setup) {''')
replace('\t\tapple_rtkit_send_message(rtk, ep, reply, NULL, false);', '''\t\terr = apple_rtkit_send_message(rtk, ep, reply, NULL, false);
\t\tif (err) {
\t\t\t/* Do not clear/free an allocation after a possibly published send. */
\t\t\tdev_err(rtk->dev, "RTKit: buffer reply failed on EP%02x: %d\\n",
\t\t\t\tep, err);
\t\t\treturn err;
\t\t}''')

replace('\t\trtk->app_ep_start = APPLE_RTKIT_APP_ENDPOINT_START_V10;', '''\t\trtk->app_ep_start = rtk->ops->ans1_endpoint5 ? 5 :
\t\t\tAPPLE_RTKIT_APP_ENDPOINT_START_V10;''')

replace('\tint min_ver = FIELD_GET(APPLE_RTKIT_MGMT_HELLO_MINVER, msg);',
        '\tint ret = -EINVAL;\n\tint min_ver = FIELD_GET(APPLE_RTKIT_MGMT_HELLO_MINVER, msg);')
replace('\tif (min_ver > APPLE_RTKIT_MAX_SUPPORTED_VERSION) {', '''\tif (min_ver > max_ver)
\t\tgoto abort_boot;

\tif (min_ver > APPLE_RTKIT_MAX_SUPPORTED_VERSION) {''')
replace('\tapple_rtkit_management_send(rtk, APPLE_RTKIT_MGMT_HELLO_REPLY, reply);', '''\tret = apple_rtkit_management_send(rtk, APPLE_RTKIT_MGMT_HELLO_REPLY, reply);
\tif (ret)
\t\tgoto abort_boot;''')
replace('abort_boot:\n\trtk->boot_result = -EINVAL;', 'abort_boot:\n\trtk->boot_result = ret;')

replace('\tint want_ver = min(APPLE_RTKIT_MAX_SUPPORTED_VERSION, max_ver);', '''\tint want_ver = min(APPLE_RTKIT_MAX_SUPPORTED_VERSION, max_ver);

\t/* Ordered RX work preserves the first negotiation failure. */
\tif (rtk->boot_result < 0)
\t\treturn;''')
replace('\tu32 base = FIELD_GET(APPLE_RTKIT_MGMT_EPMAP_BASE, msg);', '''\tu32 base = FIELD_GET(APPLE_RTKIT_MGMT_EPMAP_BASE, msg);

\tif (rtk->boot_result < 0)
\t\treturn;
\tif (rtk->version < APPLE_RTKIT_MIN_SUPPORTED_VERSION ||
\t    rtk->version > APPLE_RTKIT_MAX_SUPPORTED_VERSION) {
\t\tret = -EPROTO;
\t\tgoto abort_epmap;
\t}''')
replace('\trtk->crashed = false;', '''\t/* RX work is flushed above; reset the negotiation failure latch. */
\trtk->boot_result = 0;
\trtk->version = 0;
\trtk->app_ep_start = APPLE_RTKIT_EP_CRASHLOG;
\trtk->crashed = false;''')

replace('\tif (!buffer->is_mapped) {', '''\tif (!buffer->is_mapped) {
\t\t/* Reject truncation; retain ownership records on failure. */
\t\tif (ep == APPLE_RTKIT_EP_OSLOG) {
\t\t\tif ((buffer->iova & 0xfff) ||
\t\t\t    !FIELD_FIT(APPLE_RTKIT_OSLOG_IOVA, buffer->iova >> 12) ||
\t\t\t    !FIELD_FIT(APPLE_RTKIT_OSLOG_SIZE, buffer->size))
\t\t\t\treturn -ERANGE;
\t\t} else {
\t\t\tif ((buffer->size & 0xfff) ||
\t\t\t    !FIELD_FIT(APPLE_RTKIT_BUFFER_REQUEST_SIZE, buffer->size >> 12) ||
\t\t\t    !FIELD_FIT(APPLE_RTKIT_BUFFER_REQUEST_IOVA, buffer->iova))
\t\t\t\treturn -ERANGE;
\t\t}''')

replace('''\trtk->syslog_n_entries = FIELD_GET(APPLE_RTKIT_SYSLOG_N_ENTRIES, msg);
\trtk->syslog_msg_size = FIELD_GET(APPLE_RTKIT_SYSLOG_MSG_SIZE, msg);

\trtk->syslog_msg_buffer = kzalloc(rtk->syslog_msg_size, GFP_KERNEL);''', '''\tsize_t entries = FIELD_GET(APPLE_RTKIT_SYSLOG_N_ENTRIES, msg);
\tsize_t size = FIELD_GET(APPLE_RTKIT_SYSLOG_MSG_SIZE, msg);

\t/* Notifications run on the ordered RTKit workqueue. Invalidate the
\t * old layout before accepting a replacement or allocation failure.
\t */
\tkfree(rtk->syslog_msg_buffer);
\trtk->syslog_msg_buffer = NULL;
\trtk->syslog_n_entries = 0;
\trtk->syslog_msg_size = 0;
\tif (!entries || !size)
\t\treturn;
\trtk->syslog_msg_buffer = kzalloc(size, GFP_KERNEL);
\tif (!rtk->syslog_msg_buffer)
\t\treturn;
\trtk->syslog_n_entries = entries;
\trtk->syslog_msg_size = size;''')

replace('if (idx > rtk->syslog_n_entries) {', '''if (!rtk->syslog_msg_size || idx >= rtk->syslog_n_entries ||
\t    idx >= rtk->syslog_buffer.size / entry_size) {''')

replace('''\tif (!ops)
\t\treturn ERR_PTR(-EINVAL);''', '''\tif (!ops || (ops->ans1_endpoint5 &&
\t    (!ops->shmem_setup || !ops->shmem_destroy)))
\t\treturn ERR_PTR(-EINVAL);
\t/* ANS1 shared buffers require caller ownership: stopping mailbox
\t * work or receiving a panic does not establish DMA quiescence.
\t */''')

header_source = ROOT / 'artifacts/ans-baseline-kernel/include/linux/soc/apple/rtkit.h'
header_raw = header_source.read_bytes()
if hashlib.sha256(header_raw).hexdigest() != '7a07e272a302272bb42125a8b0cccb9b5a585ea635cb31d24e3341eba315f906':
    raise ValueError('unexpected RTKit public header')
header_original = header_raw.decode()
anchor = '\tvoid (*shmem_destroy)(void *cookie, struct apple_rtkit_shmem *bfr);'
if header_original.count(anchor) != 1:
    raise ValueError('unexpected ops layout')
header = header_original.replace(anchor, anchor + '''
\t/* Opt-in old ANS1 protocol-10 application endpoint 5; default is 6.
\t * Requires rebuilding all clients with this ops layout.
\t */
\tbool ans1_endpoint5;''')

replace('EXPORT_SYMBOL_GPL(apple_rtkit_app_ep_to_ep);', '''EXPORT_SYMBOL_GPL(apple_rtkit_app_ep_to_ep);

/* ANS1 opt-in only. Call after successful boot, before starting the app EP.
 * Prefer endpoint 6 over 5 for protocol 10, as in pinned m1n1 ans1.c.
 */
u8 apple_rtkit_ans1_endpoint(struct apple_rtkit *rtk)
{
\tif (!rtk->ops->ans1_endpoint5 || rtk->boot_result ||
\t    !apple_rtkit_is_running(rtk))
\t\treturn 0;
\tif (rtk->version == 10) {
\t\tif (test_bit(6, rtk->endpoints))
\t\t\treturn 6;
\t\tif (test_bit(5, rtk->endpoints))
\t\t\treturn 5;
\t} else if ((rtk->version == 11 || rtk->version == 12) &&
\t\t   test_bit(32, rtk->endpoints)) {
\t\treturn 32;
\t}
\treturn 0;
}
EXPORT_SYMBOL_GPL(apple_rtkit_ans1_endpoint);''')
header = header.replace('#endif /* _LINUX_APPLE_RTKIT_H_ */', '''/* ANS1 opt-in: advertised endpoint after successful boot, or zero. */
u8 apple_rtkit_ans1_endpoint(struct apple_rtkit *rtk);

#endif /* _LINUX_APPLE_RTKIT_H_ */''')

output = ROOT / 'artifacts/ans-rtkit-build'
output.mkdir(parents=True, exist_ok=True)
(output / 'rtkit.c').write_text(text, encoding='utf-8', newline='\n')
for name in ('rtkit-internal.h',):
    shutil.copyfile(source.with_name(name), output / name)
# Shared structure offsets must match the companion polling mailbox draft.
shutil.copyfile(ROOT / 'artifacts/ans-akf-mailbox/mailbox.h', output / 'mailbox.h')
(output / 'apple-rtkit.h').write_text(header, encoding='utf-8', newline='\n')
internal = (output / 'rtkit-internal.h').read_text()
(output / 'rtkit-internal.h').write_text(internal.replace(
    '#include <linux/soc/apple/rtkit.h>', '#include "apple-rtkit.h"'),
    encoding='utf-8', newline='\n')
(output / 'Makefile').write_text('obj-m += rtkit.o\n', encoding='utf-8')
patch = ''.join(difflib.unified_diff(original.splitlines(True), text.splitlines(True),
    fromfile='a/drivers/soc/apple/rtkit.c', tofile='b/drivers/soc/apple/rtkit.c'))
patch += ''.join(difflib.unified_diff(header_original.splitlines(True), header.splitlines(True),
    fromfile='a/include/linux/soc/apple/rtkit.h', tofile='b/include/linux/soc/apple/rtkit.h'))
(HERE / 'rtkit-retry-draft.patch').write_text(patch, encoding='utf-8', newline='\n')
print('Prepared RTKit source and patch for offline compilation only.')
