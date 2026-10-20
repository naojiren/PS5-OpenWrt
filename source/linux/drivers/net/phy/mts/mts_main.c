// SPDX-License-Identifier: GPL-2.0-only
/*
 * PlayStation 5 Gigabit Ethernet driver
 *
 * Based on the MediaTek Star Ethernet MAC (mtk_star_emac).
 */

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/module.h>
#include <linux/pci.h>
#include <linux/netdevice.h>
#include <linux/etherdevice.h>
#include <linux/ethtool.h>
#include <linux/interrupt.h>
#include <linux/delay.h>
#include <linux/iopoll.h>
#include <linux/crc32.h>
#include <linux/bitrev.h>
#include <linux/ps5.h>

#include "mts.h"

#define PCI_DEVICE_ID_GBE	0x9104
#define PCI_DEVICE_ID_SPCIE	0x9107

static void gbe_write_mac(struct gbe_priv *p, const u8 *addr)
{
	gbe_wr(p, GBE_REG_MAC_HI, (addr[0] << 8) | addr[1]);
	gbe_wr(p, GBE_REG_MAC_LO,
	       (addr[2] << 24) | (addr[3] << 16) | (addr[4] << 8) | addr[5]);
}

/* the glue is a seperate pci function, grab it too :) */
static int gbe_glue_map(struct gbe_priv *p)
{
	struct pci_dev *glue;

	glue = pci_get_device(PCI_VENDOR_ID_SONY, PCI_DEVICE_ID_SPCIE, NULL);
	if (!glue)
		return -ENODEV;

	if (!(pci_resource_flags(glue, 4) & IORESOURCE_MEM)) {
		pci_dev_put(glue);
		return -ENODEV;
	}

	p->glue_base = ioremap(pci_resource_start(glue, 4),
			       pci_resource_len(glue, 4));
	if (!p->glue_base) {
		pci_dev_put(glue);
		return -ENOMEM;
	}

	p->glue_pdev = glue;
	return 0;
}

static void gbe_glue_unmap(struct gbe_priv *p)
{
	if (p->glue_base) {
		iounmap(p->glue_base);
		p->glue_base = NULL;
	}
	if (p->glue_pdev) {
		pci_dev_put(p->glue_pdev);
		p->glue_pdev = NULL;
	}
}

/* MAC address lives at offset 0x3000 in Salina Glue BAR4 scratchpad */
static int gbe_read_glue_mac(struct gbe_priv *p, u8 *addr)
{
	int i;

	if (!p->glue_base)
		return -ENODEV;

	for (i = 0; i < ETH_ALEN; i++)
		addr[i] = readb(p->glue_base + 0x3000 + i);
	return 0;
}

/* writing 9 to the reset reg pulses the whole MAC, needs a short settle */
static void gbe_reset(struct gbe_priv *p)
{
	gbe_wr(p, GBE_REG_RESET, 9);
	usleep_range(680, 1000);
}

/* mark every tx slot done+free so the chip leaves em alone till we arm one */
static void gbe_init_tx_ring(struct gbe_priv *p)
{
	int i;

	for (i = 0; i < GBE_RING_SIZE; i++) {
		p->tx_ring[i].flags = cpu_to_le32(GBE_DESC_DONE |
			(i == GBE_RING_SIZE - 1 ? GBE_DESC_WRAP : 0));
		p->tx_ring[i].buf_addr = 0;
		p->tx_ring[i].word2 = cpu_to_le32(GBE_DESC_W2_ARM);
		p->tx_ring[i].word3 = 0;
	}
	p->tx_head = p->tx_tail = 0;
	p->tx_scratch_off = 0;
}

/* point each rx slot at its pool buffer and give it back to teh chip */
static void gbe_rx_fill(struct gbe_priv *p)
{
	int i;

	for (i = 0; i < GBE_RING_SIZE; i++) {
		p->rx_ring[i].buf_addr = cpu_to_le32(p->rx_pool_dma +
						     i * GBE_DESC_RX_LEN);
		p->rx_ring[i].word2 = 0;
		p->rx_ring[i].word3 = 0;
		dma_wmb();
		p->rx_ring[i].flags = cpu_to_le32(GBE_DESC_RX_LEN |
			(i == GBE_RING_SIZE - 1 ? GBE_DESC_WRAP : 0));
	}
	p->rx_head = 0;
}

static void gbe_init_rings_hw(struct gbe_priv *p)
{
	gbe_init_tx_ring(p);

	wmb();

	gbe_wr(p, GBE_REG_TX_RING_BASE, p->tx_ring_dma);
	gbe_wr(p, GBE_REG_TX_RING_CUR, p->tx_ring_dma);
	gbe_wr(p, GBE_REG_RX_RING_BASE, p->rx_ring_dma);
	gbe_wr(p, GBE_REG_RX_RING_CUR, p->rx_ring_dma);

	/* toggle bit6 to clear any stale LSO cause latched from before init */
	gbe_clr(p, GBE_REG_TXKICK, BIT(6));
	gbe_set(p, GBE_REG_TXKICK, BIT(6));

	gbe_set(p, GBE_REG_TX_DMA_CTRL, BIT(0));
	gbe_set(p, GBE_REG_RX_DMA_CTRL, BIT(0));
	gbe_wr(p, GBE_REG_IER, GBE_IER_MASK);
}

/* tell both dma engines to stop, then jsut spin till the bit clears */
static void gbe_stop_dma(struct gbe_priv *p)
{
	int i;

	gbe_wr(p, GBE_REG_IER, 0);

	gbe_set(p, GBE_REG_TX_DMA_CTRL, GBE_DMA_STOP);
	for (i = 0; i < 1000000 &&
	     (gbe_rd(p, GBE_REG_TX_DMA_CTRL) & GBE_DMA_STOP); i++)
		udelay(1);

	gbe_set(p, GBE_REG_RX_DMA_CTRL, GBE_DMA_STOP);
	for (i = 0; i < 1000000 &&
	     (gbe_rd(p, GBE_REG_RX_DMA_CTRL) & GBE_DMA_STOP); i++)
		udelay(1);
}

/* full bringup: reset, clocks, phy, then the magic mode/serdes vaules */
static void gbe_init_hw(struct gbe_priv *p)
{
	gbe_reset(p);
	gbe_set(p, GBE_REG_CLK_CTRL, GBE_CLK_ENABLE);
	gbe_phy_init(p);
	gbe_clr(p, GBE_REG_CTRL, BIT(7));
	gbe_wr(p, GBE_REG_SERDES, GBE_SERDES_1G);
	gbe_wr(p, GBE_REG_MODE, (gbe_rd(p, GBE_REG_MODE) & 0xffffff6e) | 0x81);
	gbe_wr(p, GBE_REG_RXBUF, 0x10100);
	gbe_write_mac(p, p->netdev->dev_addr);
	gbe_wr(p, GBE_REG_COAL, GBE_COAL_VAL);
}

/* the two rings + tx bounce scratch + rx pool, all dma coherent */
static int gbe_alloc_rings(struct gbe_priv *p)
{
	p->tx_ring = dma_alloc_coherent(&p->pdev->dev, GBE_DESC_RING_BYTES,
					&p->tx_ring_dma, GFP_KERNEL);
	if (!p->tx_ring)
		return -ENOMEM;

	p->rx_ring = dma_alloc_coherent(&p->pdev->dev, GBE_DESC_RING_BYTES,
					&p->rx_ring_dma, GFP_KERNEL);
	if (!p->rx_ring)
		goto err_rx;

	p->tx_scratch = dma_alloc_coherent(&p->pdev->dev, GBE_TX_SCRATCH_SIZE,
					   &p->tx_scratch_dma, GFP_KERNEL);
	if (!p->tx_scratch)
		goto err_scratch;

	p->rx_pool = dma_alloc_coherent(&p->pdev->dev, GBE_RX_POOL_SIZE,
					&p->rx_pool_dma, GFP_KERNEL);
	if (!p->rx_pool)
		goto err_pool;

	return 0;

err_pool:
	dma_free_coherent(&p->pdev->dev, GBE_TX_SCRATCH_SIZE,
			  p->tx_scratch, p->tx_scratch_dma);
err_scratch:
	dma_free_coherent(&p->pdev->dev, GBE_DESC_RING_BYTES,
			  p->rx_ring, p->rx_ring_dma);
err_rx:
	dma_free_coherent(&p->pdev->dev, GBE_DESC_RING_BYTES,
			  p->tx_ring, p->tx_ring_dma);
	return -ENOMEM;
}

static void gbe_free_rings(struct gbe_priv *p)
{
	if (p->tx_ring)
		dma_free_coherent(&p->pdev->dev, GBE_DESC_RING_BYTES,
				  p->tx_ring, p->tx_ring_dma);
	if (p->rx_ring)
		dma_free_coherent(&p->pdev->dev, GBE_DESC_RING_BYTES,
				  p->rx_ring, p->rx_ring_dma);
	if (p->tx_scratch)
		dma_free_coherent(&p->pdev->dev, GBE_TX_SCRATCH_SIZE,
				  p->tx_scratch, p->tx_scratch_dma);
	if (p->rx_pool)
		dma_free_coherent(&p->pdev->dev, GBE_RX_POOL_SIZE,
				  p->rx_pool, p->rx_pool_dma);
}

/* clean up the tx descriptors the chip finished, wake the queue if we stopped it */
static void gbe_tx_complete(struct gbe_priv *p)
{
	unsigned int tail = p->tx_tail;

	while (tail != p->tx_head) {
		struct gbe_desc *d = &p->tx_ring[tail];
		u32 flags = le32_to_cpu(d->flags);
		u32 w2    = le32_to_cpu(d->word2);

		if (!(flags & GBE_DESC_DONE))
			break;

		/* chip reuses word2 < 0xffff0000 as ownership sentinel on ring wrap */
		if (w2 >= 0xffff0000)
			break;

		/* re-arm it so the slot reads free next time round the ring */
		d->word2 = cpu_to_le32(w2 | 0xffff0000);

		p->cnt_tx_completed++;
		tail = (tail + 1) % GBE_RING_SIZE;
	}
	p->tx_tail = tail;

	if (netif_queue_stopped(p->netdev))
		netif_wake_queue(p->netdev);
}

/* grab whatever rx slots are done up to budget, copy em out and re-arm */
static int gbe_rx_poll(struct gbe_priv *p, int budget)
{
	struct net_device *dev = p->netdev;
	unsigned int i = p->rx_head;
	int done = 0;

	while (done < budget &&
	       (le32_to_cpu(p->rx_ring[i].flags) & GBE_DESC_DONE)) {
		u32 flags = le32_to_cpu(p->rx_ring[i].flags);
		u32 len = flags & GBE_DESC_RX_LEN_MASK;

		netdev_dbg(dev, "rx[%u] len=%u flags=%#x w2=%#x\n", i, len,
			   flags, le32_to_cpu(p->rx_ring[i].word2));

		if (len >= ETH_ZLEN && len <= GBE_DESC_RX_LEN) {
			struct sk_buff *skb;
			const u8 *src = (const u8 *)p->rx_pool +
					i * GBE_DESC_RX_LEN;

			p->cnt_rx_pkts++;
			if (is_broadcast_ether_addr(src))
				p->cnt_rx_bcast++;
			else if (is_multicast_ether_addr(src))
				p->cnt_rx_mcast++;

			skb = netdev_alloc_skb_ip_align(dev, len);
			if (skb) {
				skb_put_data(skb, src, len);
				skb->protocol = eth_type_trans(skb, dev);
				netif_rx(skb);
				dev->stats.rx_packets++;
				dev->stats.rx_bytes += len;
			} else {
				p->cnt_rx_nomem++;
				dev->stats.rx_dropped++;
			}
		} else {
			p->cnt_rx_bad_len++;
			dev->stats.rx_errors++;
		}

		/* hand the slot back to the chip */
		p->rx_ring[i].word2 = 0;
		p->rx_ring[i].word3 = 0;
		dma_wmb();
		p->rx_ring[i].flags = cpu_to_le32(GBE_DESC_RX_LEN |
			(i == GBE_RING_SIZE - 1 ? GBE_DESC_WRAP : 0));

		done++;
		i = (i + 1) % GBE_RING_SIZE;
	}
	p->rx_head = i;

	if (done)
		gbe_set(p, GBE_REG_RX_DMA_CTRL, GBE_DMA_KICK);

	return done;
}

static netdev_tx_t gbe_xmit(struct sk_buff *skb, struct net_device *dev)
{
	struct gbe_priv *p = netdev_priv(dev);
	unsigned int head, off, aligned;
	unsigned int len = skb->len;
	unsigned long flags;

	if (len < ETH_ZLEN)
		len = ETH_ZLEN;
	if (len > GBE_RX_BUF_LEN) {
		p->cnt_tx_drop_big++;
		dev->stats.tx_dropped++;
		dev_kfree_skb_any(skb);
		return NETDEV_TX_OK;
	}

	spin_lock_irqsave(&p->lock, flags);

	/* free up whatever the chip already finished before we go looking for room */
	gbe_tx_complete(p);

	head = p->tx_head;
	if (((head + 1) % GBE_RING_SIZE) == p->tx_tail) {
		p->cnt_tx_busy++;
		netif_stop_queue(dev);
		spin_unlock_irqrestore(&p->lock, flags);
		return NETDEV_TX_BUSY;
	}

	p->cnt_tx_pkts++;

	/* wrap scratch offset if packet doesn't fit at the end */
	aligned = (len + 0x7f) & ~0x7fu;
	off = p->tx_scratch_off;
	if (off + aligned > GBE_TX_SCRATCH_SIZE)
		off = 0;
	p->tx_scratch_off = off + aligned;
	if (p->tx_scratch_off >= GBE_TX_SCRATCH_SIZE)
		p->tx_scratch_off = 0;

	/* copy into the bounce region and zero-pad shrot frames */
	skb_copy_bits(skb, 0, (u8 *)p->tx_scratch + off, skb->len);
	if (len > skb->len)
		memset((u8 *)p->tx_scratch + off + skb->len, 0, len - skb->len);

	p->tx_ring[head].buf_addr = cpu_to_le32(p->tx_scratch_dma + off);
	p->tx_ring[head].word2 = cpu_to_le32(GBE_DESC_W2_TX);
	p->tx_ring[head].word3 = 0;
	dma_wmb();
	p->tx_ring[head].flags = cpu_to_le32((len & GBE_DESC_LEN_MASK) |
			GBE_DESC_SOP | GBE_DESC_EOP |
			(head == GBE_RING_SIZE - 1 ? GBE_DESC_WRAP : 0));

	netdev_dbg(dev, "tx[%u] len=%u off=%#x flags=%#x\n", head, len,
		   off, le32_to_cpu(p->tx_ring[head].flags));

	p->tx_head = (head + 1) % GBE_RING_SIZE;

	/* if the ring is filling up clean it again so we dont wedge under load :C */
	if ((p->tx_head + GBE_RING_SIZE - p->tx_tail) % GBE_RING_SIZE > GBE_RING_SIZE / 2)
		gbe_tx_complete(p);

	gbe_set(p, GBE_REG_TX_DMA_CTRL, GBE_DMA_KICK);

	dev->stats.tx_packets++;
	dev->stats.tx_bytes += len;

	spin_unlock_irqrestore(&p->lock, flags);
	dev_consume_skb_any(skb);
	return NETDEV_TX_OK;
}

static int gbe_set_mac_address(struct net_device *dev, void *addr)
{
	struct gbe_priv *p = netdev_priv(dev);
	struct sockaddr *sa = addr;

	if (!is_valid_ether_addr(sa->sa_data))
		return -EADDRNOTAVAIL;

	eth_hw_addr_set(dev, sa->sa_data);
	gbe_write_mac(p, dev->dev_addr);
	return 0;
}

static u32 gbe_mc_hash(const u8 *addr)
{
	u8 rev[ETH_ALEN];
	u32 crc;
	int i;

	for (i = 0; i < ETH_ALEN; i++)
		rev[i] = bitrev8(addr[i]);

	crc = crc32_be(~0, rev, ETH_ALEN);
	return (crc & 7) + (crc >> 27) * 8;
}

static void gbe_set_rx_mode(struct net_device *dev)
{
	struct gbe_priv *p = netdev_priv(dev);
	struct netdev_hw_addr *ha;
	u32 val;
	int i;

	if (dev->flags & IFF_PROMISC) {
		gbe_set(p, GBE_REG_MODE, GBE_MODE_PROMISC);
		return;
	}

	gbe_clr(p, GBE_REG_MODE, GBE_MODE_PROMISC);

	if (dev->flags & IFF_ALLMULTI) {
		for (i = 0; i < GBE_MC_HASH_BITS; i++)
			gbe_wr(p, GBE_REG_MC_HASH, GBE_MC_HASH_SET | i);
		return;
	}

	gbe_wr(p, GBE_REG_MC_HASH, GBE_MC_HASH_CLEAR);
	if (readl_poll_timeout_atomic(p->base + GBE_REG_MC_HASH, val,
				      val & GBE_MC_HASH_CLEARED, 1, 10000))
		netdev_warn(dev, "mc hash clear timeout\n");

	netdev_for_each_mc_addr(ha, dev) {
		gbe_wr(p, GBE_REG_MC_HASH, GBE_MC_HASH_SET | gbe_mc_hash(ha->addr));
		if (readl_poll_timeout_atomic(p->base + GBE_REG_MC_HASH, val,
					      !(val & GBE_MC_HASH_BUSY), 1, 10000))
			netdev_warn(dev, "mc hash set timeout\n");
	}
}

static void gbe_get_drvinfo(struct net_device *dev, struct ethtool_drvinfo *info)
{
	strscpy(info->driver, KBUILD_MODNAME, sizeof(info->driver));
}

static const struct ethtool_ops gbe_ethtool_ops = {
	.get_drvinfo	= gbe_get_drvinfo,
	.get_link	= ethtool_op_get_link,
};

/* bit0 of the link reg is carrier, just mirror it into netdev */
static void gbe_link_change(struct gbe_priv *p)
{
	u32 link_reg = gbe_rd(p, GBE_REG_LINK);
	int up = link_reg & BIT(0);

	if (up == p->link_up)
		return;

	p->link_up = up;
	if (up) {
		p->cnt_link_up++;
		netif_carrier_on(p->netdev);
		netdev_info(p->netdev, "link up (reg=%#x)\n", link_reg);
	} else {
		p->cnt_link_down++;
		netif_carrier_off(p->netdev);
		netdev_info(p->netdev, "link down (reg=%#x)\n", link_reg);
	}
}

static void gbe_dump_stats(struct gbe_priv *p)
{
	netdev_dbg(p->netdev,
		"stats: irq=%u (link=%u tx=%u rx=%u err=%u lso=%u) "
		"tx=%u (busy=%u drop_big=%u done=%u) "
		"rx=%u (bcast=%u mcast=%u badlen=%u nomem=%u) "
		"link_up=%u link_down=%u lso_recover=%u link_reg=%#x\n",
		p->cnt_irq, p->cnt_irq_link, p->cnt_irq_tx, p->cnt_irq_rx,
		p->cnt_irq_err, p->cnt_irq_lso,
		p->cnt_tx_pkts, p->cnt_tx_busy, p->cnt_tx_drop_big,
		p->cnt_tx_completed,
		p->cnt_rx_pkts, p->cnt_rx_bcast, p->cnt_rx_mcast,
		p->cnt_rx_bad_len, p->cnt_rx_nomem,
		p->cnt_link_up, p->cnt_link_down, p->cnt_lso_recover,
		gbe_rd(p, GBE_REG_LINK));
}

/* link irq is masked off (autoneg pulses storm it lol), so poll it once a sec */
static void gbe_link_poll_work(struct work_struct *work)
{
	struct gbe_priv *p = container_of(to_delayed_work(work),
					  struct gbe_priv, link_poll);
	unsigned long delay = HZ;

	gbe_link_change(p);

	/*
	 * on a cold boot the chip sometimes just never fires its first irq and
	 * napi sits there doing nothing. if the irq count hasnt moved since last
	 * tick the msi is dead -- kick napi by hand and re-arm the mask. msi is the
	 * only irq source (no intx pin), so while it stays dead we keep polling fast
	 * (GBE_POLL_FALLBACK_MS) instead of once a second, or interactive rx lags by
	 * up to a second. as soon as real irqs start arriving we drop back to HZ.
	 */
	if (netif_running(p->netdev) && p->cnt_irq == p->irq_watchdog) {
		napi_schedule(&p->napi);
		gbe_wr(p, GBE_REG_IER, GBE_IER_MASK);
		delay = max_t(unsigned long, 1, msecs_to_jiffies(GBE_POLL_FALLBACK_MS));
	}
	p->irq_watchdog = p->cnt_irq;

	/* dump stats roughly every 10s regardless of the current poll cadence */
	if (++p->poll_tick >= 10 * HZ / delay) {
		gbe_dump_stats(p);
		p->poll_tick = 0;
	}

	schedule_delayed_work(&p->link_poll, delay);
}

/*
 * the chip latches an lso error and then just sulks, wont tx until the
 * ring gets rebuilt. so tear it down and stand it back up, same toggle as init.
 */
static void gbe_lso_recover(struct gbe_priv *p)
{
	p->cnt_lso_recover++;
	netdev_warn(p->netdev, "LSO error, rebuilding TX ring (cnt=%u)\n",
		    p->cnt_lso_recover);

	spin_lock(&p->lock);
	netif_stop_queue(p->netdev);

	gbe_clr(p, GBE_REG_TXKICK, BIT(6));
	gbe_set(p, GBE_REG_TXKICK, BIT(6));

	gbe_init_tx_ring(p);
	dma_wmb();

	gbe_wr(p, GBE_REG_TX_RING_BASE, p->tx_ring_dma);
	gbe_wr(p, GBE_REG_TX_RING_CUR, p->tx_ring_dma);
	gbe_set(p, GBE_REG_TX_DMA_CTRL, BIT(0));

	netif_wake_queue(p->netdev);
	spin_unlock(&p->lock);
}

/* napi: do tx, then rx, turn irqs back on once we drop under budget */
static int gbe_poll(struct napi_struct *napi, int budget)
{
	struct gbe_priv *p = container_of(napi, struct gbe_priv, napi);
	int rx_done;

	/* isr flags this when it sees an lso cause, deal with it out of hardirq */
	if (test_and_clear_bit(GBE_ST_LSO_RECOVER, &p->state))
		gbe_lso_recover(p);

	spin_lock(&p->lock);
	gbe_tx_complete(p);
	gbe_set(p, GBE_REG_TX_DMA_CTRL, GBE_DMA_KICK);
	spin_unlock(&p->lock);

	rx_done = gbe_rx_poll(p, budget);

	if (rx_done < budget) {
		u32 isr;

		napi_complete_done(napi, rx_done);
		gbe_wr(p, GBE_REG_IER, GBE_IER_MASK);
		/* chip wont send a fresh msi for stuff that landed while ier was
		   off, so re-check isr and re-kick or interrupts just freeze.
		   ACK the causes (W1C) first: otherwise a latched/undelivered
		   cause (the msi-silent cold-boot case) keeps this condition
		   permanently true and spins napi at ~30k polls/s, pinning a cpu. */
		isr = gbe_rd(p, GBE_REG_ISR) & GBE_IER_MASK;
		if (isr) {
			gbe_wr(p, GBE_REG_ISR, isr);
			if (napi_schedule_prep(&p->napi)) {
				gbe_wr(p, GBE_REG_IER, 0);
				__napi_schedule(&p->napi);
			}
		}
	}
	return rx_done;
}

static irqreturn_t gbe_isr(int irq, void *data)
{
	struct gbe_priv *p = data;
	u32 status;

	status = gbe_rd(p, GBE_REG_ISR);
	if (!status)
		return IRQ_NONE;

	/* ack everyhting we just read off */
	gbe_wr(p, GBE_REG_ISR, status);

	p->cnt_irq++;
	if (status & GBE_ISR_LINK)
		p->cnt_irq_link++;
	if (status & GBE_ISR_TX_DONE)
		p->cnt_irq_tx++;
	if (status & GBE_ISR_RX_DONE)
		p->cnt_irq_rx++;
	if (status & GBE_ISR_ERRORS)
		p->cnt_irq_err++;
	if (status & GBE_ISR_LSO_RECOVER)
		p->cnt_irq_lso++;

	if (status & GBE_ISR_LINK)
		gbe_link_change(p);

	if (status & GBE_ISR_ERRORS) {
		u32 err = status & GBE_ISR_ERRORS;

		net_err_ratelimited("%s: HW error %#x%s%s%s%s%s%s%s\n",
			netdev_name(p->netdev), err,
			err & GBE_ERR_LSO_FIFO  ? " lso-fifo-empty" : "",
			err & GBE_ERR_LSO_PROTO ? " lso-proto" : "",
			err & GBE_ERR_RX_AXI    ? " rx-axi" : "",
			err & GBE_ERR_IP_CKSUM  ? " ip-cksum" : "",
			err & GBE_ERR_TCP_CKSUM ? " tcp-cksum" : "",
			err & GBE_ERR_UDP_CKSUM ? " udp-cksum" : "",
			err & GBE_ERR_RX_PCODE  ? " rx-pcode" : "");
		p->netdev->stats.rx_errors++;
	}

	if (status & GBE_ISR_LSO_RECOVER)
		set_bit(GBE_ST_LSO_RECOVER, &p->state);

	/* mask irqs and let napi do the ring work out of hardirq */
	if (napi_schedule_prep(&p->napi)) {
		gbe_wr(p, GBE_REG_IER, 0);
		__napi_schedule(&p->napi);
	}

	return IRQ_HANDLED;
}

static int gbe_open(struct net_device *dev)
{
	struct gbe_priv *p = netdev_priv(dev);
	int ret;

	ret = request_irq(p->irq, gbe_isr, IRQF_SHARED, dev->name, p);
	if (ret)
		return ret;

	p->link_up = 0;
	netif_carrier_off(dev);

	gbe_init_hw(p);
	gbe_rx_fill(p);
	gbe_init_rings_hw(p);
	napi_enable(&p->napi);
	netif_start_queue(dev);

	gbe_link_change(p);
	schedule_delayed_work(&p->link_poll, HZ);

	return 0;
}

static int gbe_stop(struct net_device *dev)
{
	struct gbe_priv *p = netdev_priv(dev);

	netif_stop_queue(dev);
	netif_carrier_off(dev);

	cancel_delayed_work_sync(&p->link_poll);

	gbe_stop_dma(p);

	free_irq(p->irq, p);
	napi_disable(&p->napi);
	return 0;
}

/* stack gave up on us, stop tx dma and stand the ring back up */
static void gbe_tx_timeout(struct net_device *dev, unsigned int txqueue)
{
	struct gbe_priv *p = netdev_priv(dev);
	int i;

	spin_lock_bh(&p->lock);

	gbe_set(p, GBE_REG_TX_DMA_CTRL, GBE_DMA_STOP);
	for (i = 0; i < 1000 && (gbe_rd(p, GBE_REG_TX_DMA_CTRL) & GBE_DMA_STOP); i++)
		;

	gbe_init_tx_ring(p);
	dma_wmb();

	gbe_wr(p, GBE_REG_TX_RING_BASE, p->tx_ring_dma);
	gbe_wr(p, GBE_REG_TX_RING_CUR, p->tx_ring_dma);

	gbe_clr(p, GBE_REG_TXKICK, BIT(6));
	gbe_set(p, GBE_REG_TXKICK, BIT(6));

	gbe_set(p, GBE_REG_TX_DMA_CTRL, BIT(0) | GBE_DMA_KICK);

	netif_wake_queue(dev);
	spin_unlock_bh(&p->lock);
}

static const struct net_device_ops gbe_netdev_ops = {
	.ndo_open		= gbe_open,
	.ndo_stop		= gbe_stop,
	.ndo_start_xmit		= gbe_xmit,
	.ndo_tx_timeout		= gbe_tx_timeout,
	.ndo_set_mac_address	= gbe_set_mac_address,
	.ndo_set_rx_mode	= gbe_set_rx_mode,
	.ndo_validate_addr	= eth_validate_addr,
};

static int gbe_probe(struct pci_dev *pdev, const struct pci_device_id *id)
{
	struct net_device *netdev;
	struct gbe_priv *p;
	u8 mac[ETH_ALEN];
	int ret;

	if (!spcie_is_initialized())
		return -EPROBE_DEFER;

	ret = pcim_enable_device(pdev);
	if (ret)
		return ret;

	/* GBE registers are in BAR0 */
	ret = pcim_iomap_regions(pdev, BIT(0), KBUILD_MODNAME);
	if (ret)
		return ret;

	pci_set_master(pdev);

	ret = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(32));
	if (ret)
		return ret;

	netdev = alloc_etherdev(sizeof(*p));
	if (!netdev)
		return -ENOMEM;

	SET_NETDEV_DEV(netdev, &pdev->dev);

	p		= netdev_priv(netdev);
	p->netdev	= netdev;
	p->pdev		= pdev;
	p->base		= pcim_iomap_table(pdev)[0];
	spin_lock_init(&p->lock);

	ret = gbe_alloc_rings(p);
	if (ret)
		goto err_free;

	ret = gbe_glue_map(p);
	if (ret) {
		dev_err(&pdev->dev, "probe: glue BAR4 map failed: %d\n", ret);
		goto err_rings;
	}

	if (gbe_read_glue_mac(p, mac) == 0 && is_valid_ether_addr(mac)) {
		eth_hw_addr_set(netdev, mac);
	} else {
		eth_hw_addr_random(netdev);
		dev_warn(&pdev->dev, "no MAC from Salina Glue, using random %pM\n",
			 netdev->dev_addr);
	}

	netdev->netdev_ops	= &gbe_netdev_ops;
	netdev->ethtool_ops	= &gbe_ethtool_ops;
	netdev->watchdog_timeo	= 5 * HZ;

	netif_napi_add(netdev, &p->napi, gbe_poll);
	INIT_DELAYED_WORK(&p->link_poll, gbe_link_poll_work);

	/* device has no intx pin so msi is the only optoin here */
	ret = pci_alloc_irq_vectors(pdev, 1, 1, PCI_IRQ_MSI | PCI_IRQ_INTX);
	if (ret < 0) {
		dev_err(&pdev->dev, "probe: no IRQ vectors: %d\n", ret);
		goto err_napi;
	}
	p->irq = pci_irq_vector(pdev, 0);

	pci_set_drvdata(pdev, netdev);

	ret = register_netdev(netdev);
	if (ret)
		goto err_irq;

	netif_carrier_off(netdev);

	dev_info(&pdev->dev, "Salina GBE (chip %#x)\n", spcie_get_chip_id());
	return 0;

err_irq:
	pci_free_irq_vectors(pdev);
err_napi:
	netif_napi_del(&p->napi);
	gbe_glue_unmap(p);
err_rings:
	gbe_free_rings(p);
err_free:
	free_netdev(netdev);
	return ret;
}

static void gbe_remove(struct pci_dev *pdev)
{
	struct net_device *netdev = pci_get_drvdata(pdev);
	struct gbe_priv *p = netdev_priv(netdev);

	unregister_netdev(netdev);
	netif_napi_del(&p->napi);
	pci_free_irq_vectors(pdev);
	gbe_glue_unmap(p);
	gbe_free_rings(p);
	free_netdev(netdev);
}

static const struct pci_device_id gbe_pci_tbl[] = {
	{ PCI_DEVICE(PCI_VENDOR_ID_SONY, PCI_DEVICE_ID_GBE) },
	{ }
};
MODULE_DEVICE_TABLE(pci, gbe_pci_tbl);

static struct pci_driver gbe_driver = {
	.name		= KBUILD_MODNAME,
	.id_table	= gbe_pci_tbl,
	.probe		= gbe_probe,
	.remove		= gbe_remove,
};

module_pci_driver(gbe_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Armandas Kvietkus");
MODULE_DESCRIPTION("PlayStation 5 Gigabit Ethernet driver");
