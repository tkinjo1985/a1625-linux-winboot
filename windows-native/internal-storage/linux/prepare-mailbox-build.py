"""Prepare an offline AKF mailbox build and review patch; no device operations."""
from pathlib import Path
import difflib
import hashlib
import shutil

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
source = ROOT / 'artifacts/ans-baseline-kernel/drivers/soc/apple/mailbox.c'
raw = source.read_bytes()
if hashlib.sha256(raw).hexdigest() != '6ac8541df028f3e0d99a5857f414cb19a89cc1a14dc6f83c6eb13844e58453bc':
    raise ValueError('unexpected baseline mailbox source')
original = raw.decode()
text = original


def replace(old, new):
    global text
    if text.count(old) != 1:
        raise ValueError('source anchor must occur exactly once')
    text = text.replace(old, new)


replace('#include "mailbox.h"', '#include "mailbox.h"\n#include "ans1_wire.h"')
replace('struct apple_mbox_hw {', 'struct apple_mbox_hw {\n\tbool akf_single_word;')
replace('\tu32 mbox_ctrl;\n\tlong t;', '''\tu32 mbox_ctrl;
\tu64 akf_word = 0;
\tlong t;

\t/* Validate before taking a lock or touching hardware. */
\tif (mbox->hw->akf_single_word &&
\t    !ans1_wire_encode(msg.msg1, msg.msg0, &akf_word))
\t\treturn -EINVAL;''')
replace('''\twriteq_relaxed(msg.msg0, mbox->regs + mbox->hw->a2i_send0);
\twriteq_relaxed(FIELD_PREP(APPLE_MBOX_MSG1_MSG, msg.msg1),
\t\t       mbox->regs + mbox->hw->a2i_send1);''', '''\tif (mbox->hw->akf_single_word) {
\t\twriteq_relaxed(akf_word, mbox->regs + mbox->hw->a2i_send0);
\t} else {
\t\twriteq_relaxed(msg.msg0, mbox->regs + mbox->hw->a2i_send0);
\t\twriteq_relaxed(FIELD_PREP(APPLE_MBOX_MSG1_MSG, msg.msg1),
\t\t\t       mbox->regs + mbox->hw->a2i_send1);
\t}''')
replace('''\t\tmsg.msg1 = FIELD_GET(
\t\t\tAPPLE_MBOX_MSG1_MSG,
\t\t\treadq_relaxed(mbox->regs + mbox->hw->i2a_recv1));''', '''\t\tif (mbox->hw->akf_single_word) {
\t\t\tmsg.msg1 = ans1_wire_endpoint(msg.msg0);
\t\t\tmsg.msg0 = ans1_wire_data(msg.msg0);
\t\t} else {
\t\t\tmsg.msg1 = FIELD_GET(
\t\t\t\tAPPLE_MBOX_MSG1_MSG,
\t\t\t\treadq_relaxed(mbox->regs + mbox->hw->i2a_recv1));
\t\t}''')
replace('\tenable_irq(mbox->irq_recv_not_empty);', '''\tif (mbox->hw->akf_single_word) {
\t\tu32 tx_status, rx_status;

\t\ttx_status = readl_relaxed(mbox->regs + mbox->hw->a2i_control);
\t\trx_status = readl_relaxed(mbox->regs + mbox->hw->i2a_control);
\t\tif ((tx_status | rx_status) & 0xc0000) {
\t\t\tWRITE_ONCE(mbox->akf_faulted, true);
\t\t\tpm_runtime_mark_last_busy(mbox->dev);
\t\t\tpm_runtime_put_autosuspend(mbox->dev);
\t\t\treturn -EIO;
\t\t}
\t\twritel_relaxed(tx_status | BIT(0), mbox->regs + mbox->hw->a2i_control);
\t\twritel_relaxed(rx_status | BIT(0), mbox->regs + mbox->hw->i2a_control);
\t}

\tenable_irq(mbox->irq_recv_not_empty);''')
replace('static const struct of_device_id apple_mbox_of_match[] = {', '''/* Resource starts at the AKF mailbox window (IOP base + 0x1000).
 * No firmware mapping, CPU start, or guessed IRQ numbering is added here.
 */
static const struct apple_mbox_hw apple_mbox_t7000_akf_hw = {
\t.akf_single_word = true,
\t.control_full = BIT(16),
\t.control_empty = BIT(17),
\t.a2i_control = 0x08,
\t.a2i_send0 = 0x10,
\t.i2a_control = 0x20,
\t.i2a_recv0 = 0x38,
};

static const struct of_device_id apple_mbox_of_match[] = {
\t{ .compatible = "apple,t7000-akf-mailbox", .data = &apple_mbox_t7000_akf_hw },''')

replace('\twhile (!(mbox_ctrl & mbox->hw->control_empty)) {', '''\t/* Per-call budget only; AKF IRQ retrigger policy needs hardware validation. */
\twhile (!(mbox_ctrl & mbox->hw->control_empty) &&
\t       (!mbox->hw->akf_single_word || ret < 64)) {''')
replace('\tmbox->regs = devm_platform_ioremap_resource(pdev, 0);', '''\tif (mbox->hw->akf_single_word) {
\t\tstruct resource *res;

\t\t/* This draft has evidence only for the owned J42d/T7000 target. */
\t\tif (!of_machine_is_compatible("apple,j42d") ||
\t\t    !of_machine_is_compatible("apple,t7000"))
\t\t\treturn -ENODEV;
\t\tres = platform_get_resource(pdev, IORESOURCE_MEM, 0);
\t\tif (!res || res->end < res->start ||
\t\t    resource_size(res) < 0x40 || (res->start & 7))
\t\t\treturn -EINVAL;
\t}

\tmbox->regs = devm_platform_ioremap_resource(pdev, 0);''')

replace('\twhile (mbox_ctrl & mbox->hw->control_full) {', '''\twhile (mbox_ctrl & mbox->hw->control_full) {
\t\t/* AKF retries belong to the caller's absolute request deadline.
\t\t * Never arm the unverified send-empty interrupt or spin for 500 ms.
\t\t */
\t\tif (mbox->hw->akf_single_word) {
\t\t\tspin_unlock_irqrestore(&mbox->tx_lock, flags);
\t\t\treturn -EAGAIN;
\t\t}''')

replace('int apple_mbox_start(struct apple_mbox *mbox)', '''static void apple_mbox_akf_poll_work(struct work_struct *work)
{
\tstruct apple_mbox *mbox = container_of(to_delayed_work(work),
\t\t\t\t\t     struct apple_mbox, akf_poll_work);

\tif (!READ_ONCE(mbox->active))
\t\treturn;
\tapple_mbox_poll(mbox);
\tif (READ_ONCE(mbox->active))
\t\tschedule_delayed_work(&mbox->akf_poll_work, msecs_to_jiffies(2));
}

int apple_mbox_start(struct apple_mbox *mbox)''')
replace('''\tenable_irq(mbox->irq_recv_not_empty);
\tmbox->active = true;''', '''\tif (mbox->hw->akf_single_word) {
\t\tWRITE_ONCE(mbox->active, true);
\t\tschedule_delayed_work(&mbox->akf_poll_work, 0);
\t} else {
\t\tenable_irq(mbox->irq_recv_not_empty);
\t\tmbox->active = true;
\t}''')
replace('''\tmbox->active = false;
\tdisable_irq(mbox->irq_recv_not_empty);''', '''\tWRITE_ONCE(mbox->active, false);
\tif (mbox->hw->akf_single_word)
\t\tcancel_delayed_work_sync(&mbox->akf_poll_work);
\telse
\t\tdisable_irq(mbox->irq_recv_not_empty);''')
replace('''\tmbox->irq_recv_not_empty =
\t\tplatform_get_irq_byname''', '''\tspin_lock_init(&mbox->rx_lock);
\tspin_lock_init(&mbox->tx_lock);
\tinit_completion(&mbox->tx_empty);
\tINIT_DELAYED_WORK(&mbox->akf_poll_work, apple_mbox_akf_poll_work);
\tif (mbox->hw->akf_single_word)
\t\tgoto enable_runtime;

\tmbox->irq_recv_not_empty =
\t\tplatform_get_irq_byname''')
# The original repeated lock initialization is harmless but unnecessary.
replace('''\tspin_lock_init(&mbox->rx_lock);
\tspin_lock_init(&mbox->tx_lock);
\tinit_completion(&mbox->tx_empty);

\tirqname''', '\tirqname')
replace('\tret = devm_pm_runtime_enable(dev);', 'enable_runtime:\n\tret = devm_pm_runtime_enable(dev);')

replace('''\tspin_lock_irqsave(&mbox->tx_lock, flags);
\tmbox_ctrl = readl_relaxed''', '''\tspin_lock_irqsave(&mbox->tx_lock, flags);
\tif (mbox->hw->akf_single_word && !READ_ONCE(mbox->active)) {
\t\tspin_unlock_irqrestore(&mbox->tx_lock, flags);
\t\treturn -ESHUTDOWN;
\t}
\tmbox_ctrl = readl_relaxed''')
replace('\tret = apple_mbox_poll_locked(mbox);', '''\tif (mbox->hw->akf_single_word && !READ_ONCE(mbox->active))
\t\tret = -ESHUTDOWN;
\telse
\t\tret = apple_mbox_poll_locked(mbox);''')
replace('''\tif (mbox->hw->akf_single_word)
\t\tcancel_delayed_work_sync(&mbox->akf_poll_work);
\telse''', '''\tif (mbox->hw->akf_single_word) {
\t\tunsigned long flags;

\t\tcancel_delayed_work_sync(&mbox->akf_poll_work);
\t\t/* Drain in-flight users before releasing the runtime-PM reference.
\t\t * Never hold RX and TX together: receive callbacks may send.
\t\t */
\t\tspin_lock_irqsave(&mbox->rx_lock, flags);
\t\tspin_unlock_irqrestore(&mbox->rx_lock, flags);
\t\tspin_lock_irqsave(&mbox->tx_lock, flags);
\t\tspin_unlock_irqrestore(&mbox->tx_lock, flags);
\t} else''')
replace('static int apple_mbox_probe(struct platform_device *pdev)', '''static void apple_mbox_akf_cleanup(void *data)
{
\tapple_mbox_stop(data);
}

static int apple_mbox_probe(struct platform_device *pdev)''')
replace('\tplatform_set_drvdata(pdev, mbox);', '''\tif (mbox->hw->akf_single_word) {
\t\tret = devm_add_action_or_reset(dev, apple_mbox_akf_cleanup, mbox);
\t\tif (ret)
\t\t\treturn ret;
\t}
\tplatform_set_drvdata(pdev, mbox);''')

replace('int apple_mbox_start(struct apple_mbox *mbox)',
        'static int apple_mbox_start_locked(struct apple_mbox *mbox)')
replace('EXPORT_SYMBOL(apple_mbox_start);', '''int apple_mbox_start(struct apple_mbox *mbox)
{
\tint ret;

\tif (!mbox->hw->akf_single_word)
\t\treturn apple_mbox_start_locked(mbox);
\tmutex_lock(&mbox->lifecycle_lock);
\tret = apple_mbox_start_locked(mbox);
\tmutex_unlock(&mbox->lifecycle_lock);
\treturn ret;
}
EXPORT_SYMBOL(apple_mbox_start);''')
replace('void apple_mbox_stop(struct apple_mbox *mbox)',
        'static void apple_mbox_stop_locked(struct apple_mbox *mbox)')
replace('EXPORT_SYMBOL(apple_mbox_stop);', '''void apple_mbox_stop(struct apple_mbox *mbox)
{
\tif (!mbox->hw->akf_single_word) {
\t\tapple_mbox_stop_locked(mbox);
\t\treturn;
\t}
\tmutex_lock(&mbox->lifecycle_lock);
\tapple_mbox_stop_locked(mbox);
\tmutex_unlock(&mbox->lifecycle_lock);
}
EXPORT_SYMBOL(apple_mbox_stop);''')
replace('\tINIT_DELAYED_WORK(&mbox->akf_poll_work, apple_mbox_akf_poll_work);',
        '\tmutex_init(&mbox->lifecycle_lock);\n\tINIT_DELAYED_WORK(&mbox->akf_poll_work, apple_mbox_akf_poll_work);')

# iBoot 17L256 treats AKF control bits 18/19 as fatal. Latch until removal;
# stopping host polling is not proof that firmware DMA has stopped.
replace('\tmbox_ctrl = readl_relaxed(mbox->regs + mbox->hw->a2i_control);\n\n', '''\tif (mbox->hw->akf_single_word && READ_ONCE(mbox->akf_faulted)) {
\t\tspin_unlock_irqrestore(&mbox->tx_lock, flags);
\t\treturn -EIO;
\t}
\tmbox_ctrl = readl_relaxed(mbox->regs + mbox->hw->a2i_control);
\tif (mbox->hw->akf_single_word && (mbox_ctrl & 0xc0000)) {
\t\tWRITE_ONCE(mbox->akf_faulted, true);
\t\tspin_unlock_irqrestore(&mbox->tx_lock, flags);
\t\treturn -EIO;
\t}

''')
for rx_prefix in ('\tu32 ', '\t\t'):
    rx_read = rx_prefix + 'mbox_ctrl = readl_relaxed(mbox->regs + mbox->hw->i2a_control);'
    indent = '\t' if rx_prefix == '\tu32 ' else '\t\t'
    replace(rx_read, rx_read + '\n' + '\n'.join(indent + line for line in (
        'if (mbox->hw->akf_single_word && (mbox_ctrl & 0xc0000)) {',
        '\tWRITE_ONCE(mbox->akf_faulted, true);', '\treturn -EIO;', '}')))
replace('\telse\n\t\tret = apple_mbox_poll_locked(mbox);', '''\telse if (mbox->hw->akf_single_word && READ_ONCE(mbox->akf_faulted))
\t\tret = -EIO;
\telse
\t\tret = apple_mbox_poll_locked(mbox);''')
replace('\tif (mbox->active)\n', '''\tif (mbox->hw->akf_single_word && READ_ONCE(mbox->akf_faulted))
\t\treturn -EIO;
\tif (mbox->active)
''')
replace('\tif (READ_ONCE(mbox->active))\n',
        '\tif (READ_ONCE(mbox->active) && !READ_ONCE(mbox->akf_faulted))\n')

header_raw = source.with_name('mailbox.h').read_bytes()
if hashlib.sha256(header_raw).hexdigest() != '4ac9fe47a9110c98ad0b5e7a52fc479b1b4d11373f95a4722f1a84ea6915e05d':
    raise ValueError('unexpected mailbox header')
header_original = header_raw.decode()
header = header_original.replace('#include <linux/types.h>',
    '#include <linux/types.h>\n#include <linux/workqueue.h>\n#include <linux/mutex.h>')
header = header.replace('\tbool active;', '\tbool active;\n\tbool akf_faulted;\n\tstruct delayed_work akf_poll_work;\n\tstruct mutex lifecycle_lock;')

output = ROOT / 'artifacts/ans-akf-mailbox'
output.mkdir(parents=True, exist_ok=True)
(output / 'mailbox.c').write_text(text, encoding='utf-8', newline='\n')
(output / 'mailbox.h').write_text(header, encoding='utf-8', newline='\n')
shutil.copyfile(HERE / 'ans1_wire.h', output / 'ans1_wire.h')
(output / 'Makefile').write_text('obj-m += mailbox.o\n', encoding='utf-8')
patch = ''.join(difflib.unified_diff(original.splitlines(True), text.splitlines(True),
    fromfile='a/drivers/soc/apple/mailbox.c', tofile='b/drivers/soc/apple/mailbox.c'))
patch += ''.join(difflib.unified_diff(header_original.splitlines(True), header.splitlines(True),
    fromfile='a/drivers/soc/apple/mailbox.h', tofile='b/drivers/soc/apple/mailbox.h'))
(HERE / 'mailbox-akf-draft.patch').write_text(patch, encoding='utf-8', newline='\n')
print('Prepared compile-only source and draft patch; no DT or boot artifact changed.')
