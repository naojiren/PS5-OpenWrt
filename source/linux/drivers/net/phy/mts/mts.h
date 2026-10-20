// SPDX-License-Identifier: GPL-2.0-only
/*
 * PlayStation 5 Gigabit Ethernet driver
 *
 * Based on the MediaTek Star Ethernet MAC (mtk_star_emac).
 */

#ifndef _MTS_H
#define _MTS_H

#include <linux/types.h>
#include <linux/bits.h>
#include <linux/io.h>
#include <linux/spinlock.h>
#include <linux/netdevice.h>
#include <linux/workqueue.h>

struct pci_dev;
struct sk_buff;

#define GBE_REG_SMI		0x00
#define GBE_REG_LINK		0x04
#define GBE_REG_CLK_CTRL	0x08
#define GBE_REG_CTRL		0x0c
#define GBE_REG_MODE		0x10
#define GBE_REG_MAC_HI		0x14
#define GBE_REG_MAC_LO		0x18
#define GBE_REG_MC_HASH		0x1c
#define GBE_REG_RXBUF		0x30
#define GBE_REG_TX_DMA_CTRL	0x34
#define GBE_REG_RX_DMA_CTRL	0x38
#define GBE_REG_TX_RING_CUR	0x3c
#define GBE_REG_RX_RING_CUR	0x40
#define GBE_REG_TX_RING_BASE	0x44
#define GBE_REG_RX_RING_BASE	0x48
#define GBE_REG_ISR		0x50
#define GBE_REG_IER		0x54
#define GBE_REG_SERDES		0x74
#define GBE_REG_RX_PCODE	0x78
#define GBE_REG_TXKICK		0x9c
#define GBE_REG_RESET		0xac
#define GBE_REG_TX_EN		0x1b8
#define GBE_REG_FILT_CTRL	0x1c4
#define GBE_REG_FILT_DATA	0x1c8
#define GBE_REG_RX_EN		0x1d4
#define GBE_REG_COAL		0x204

#define GBE_PCS_BASE		0x4000

#define GBE_CLK_ENABLE		0x7597c00

#define GBE_SERDES_1G		0x303277
#define GBE_SERDES_OTHER	0x304277

#define GBE_ISR_LINK		BIT(2)
#define GBE_ISR_TX_DONE		BIT(7)
#define GBE_ISR_RX_DONE		BIT(6)
#define GBE_ISR_ERRORS		0x7be600
#define GBE_ISR_LSO_RECOVER	0x500000

#define GBE_ST_LSO_RECOVER	0

#define GBE_ERR_LSO_FIFO	0x200000
#define GBE_ERR_LSO_PROTO	0x80000
#define GBE_ERR_RX_AXI		0x20000
#define GBE_ERR_IP_CKSUM	0x8000
#define GBE_ERR_TCP_CKSUM	0x4000
#define GBE_ERR_UDP_CKSUM	0x2000
#define GBE_ERR_RX_PCODE	0x400

#define GBE_MODE_PROMISC	BIT(4)
#define GBE_MC_HASH_CLEAR	BIT(31)
#define GBE_MC_HASH_CLEARED	BIT(17)
#define GBE_MC_HASH_BUSY	BIT(14)
#define GBE_MC_HASH_SET		0x7000
#define GBE_MC_HASH_BITS	256

#define GBE_COAL_VAL		0x10001388

/* this chip has no intx pin and its msi sometimes never fires (cold boot). when
 * we detect that, the link_poll work becomes the only way to service the rings,
 * so it polls this often (ms) instead of once a second to stay responsive. */
#define GBE_POLL_FALLBACK_MS	10

/* excludes bit2 (LINK) - polling link state avoids IRQ storm from autoneg pulses */
#define GBE_IER_MASK		0x5014fa

#define GBE_DMA_STOP		BIT(1)
#define GBE_DMA_KICK		BIT(2)

struct gbe_desc {
	__le32	flags;
	__le32	buf_addr;
	__le32	word2;
	__le32	word3;
};

#define GBE_DESC_DONE		BIT(31)
#define GBE_DESC_WRAP		BIT(30)
#define GBE_DESC_SOP		BIT(29)
#define GBE_DESC_EOP		BIT(28)
#define GBE_DESC_LEN_MASK	0xffff
#define GBE_DESC_RX_LEN		0x600
#define GBE_DESC_RX_LEN_MASK	0x7ff
/* idle TX descriptor word2 - chip treats anything >= 0xffff0000 as free */
#define GBE_DESC_W2_ARM		0xffff0000
/* active TX descriptor word2 */
#define GBE_DESC_W2_TX		0x4

#define GBE_RING_SIZE		256
#define GBE_DESC_RING_BYTES	(GBE_RING_SIZE * sizeof(struct gbe_desc))
#define GBE_RX_BUF_LEN		1536

#define GBE_TX_SCRATCH_SIZE	0xa0000
#define GBE_RX_POOL_SIZE	(GBE_RING_SIZE * GBE_DESC_RX_LEN)

struct gbe_priv {
	struct net_device	*netdev;
	struct pci_dev		*pdev;
	void __iomem		*base;
	/* PCS/SerDes regs live in Salina Glue (104d:9107) BAR4, not BAR0 */
	void __iomem		*glue_base;
	struct pci_dev		*glue_pdev;

	/* tx goes through a bounce scratch region, the chip wants contiguous buffers */
	struct gbe_desc		*tx_ring;
	dma_addr_t		tx_ring_dma;
	void			*tx_scratch;
	dma_addr_t		tx_scratch_dma;
	unsigned int		tx_scratch_off;
	unsigned int		tx_head;
	unsigned int		tx_tail;

	/* rx just has the chip dma straight into a slotted pool */
	struct gbe_desc		*rx_ring;
	dma_addr_t		rx_ring_dma;
	void			*rx_pool;
	dma_addr_t		rx_pool_dma;
	unsigned int		rx_head;

	struct napi_struct	napi;
	int			irq;
	int			link_up;
	unsigned long		state;
	struct delayed_work	link_poll;
	spinlock_t		lock;

	/* debug counters, dumped every now and then by the link poll work */
	u32			cnt_irq;
	u32			cnt_irq_link;
	u32			cnt_irq_tx;
	u32			cnt_irq_rx;
	u32			cnt_irq_err;
	u32			cnt_irq_lso;
	u32			cnt_tx_pkts;
	u32			cnt_tx_busy;
	u32			cnt_tx_drop_big;
	u32			cnt_tx_completed;
	u32			cnt_rx_pkts;
	u32			cnt_rx_bcast;
	u32			cnt_rx_mcast;
	u32			cnt_rx_bad_len;
	u32			cnt_rx_nomem;
	u32			cnt_lso_recover;
	u32			cnt_link_up;
	u32			cnt_link_down;
	unsigned int		poll_tick;
	/* used by link_poll_work to detect frozen IRQ delivery on cold boot */
	u32			irq_watchdog;
};

static inline u32 gbe_rd(struct gbe_priv *p, u32 reg)
{
	return readl(p->base + reg);
}

static inline void gbe_wr(struct gbe_priv *p, u32 reg, u32 val)
{
	writel(val, p->base + reg);
}

static inline void gbe_set(struct gbe_priv *p, u32 reg, u32 bits)
{
	gbe_wr(p, reg, gbe_rd(p, reg) | bits);
}

static inline void gbe_clr(struct gbe_priv *p, u32 reg, u32 bits)
{
	gbe_wr(p, reg, gbe_rd(p, reg) & ~bits);
}

int gbe_phy_init(struct gbe_priv *p);

#endif /* _MTS_H */
