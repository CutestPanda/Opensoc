#include "eth_mac.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void init_eth_mac(EthMac* eth_mac, uint32_t baseaddr){
	eth_mac->hardware = (EthMacHd*)baseaddr;
}

void cfg_eth_mac(EthMac* eth_mac, const EthMacCfg* cfg){
	eth_mac->hardware->eth_tx_buf_baseaddr = cfg->eth_tx_buf_baseaddr;
	eth_mac->hardware->eth_dsc_buf_len =
		((uint32_t)cfg->eth_tx_dsc_buf_len) |
		(((uint32_t)cfg->eth_rx_dsc_buf_len) << 8);
	eth_mac->hardware->eth_rx_buf_baseaddr = cfg->eth_rx_buf_baseaddr;
	eth_mac->hardware->mdc_div_rate = cfg->mdc_div_rate;
	eth_mac->hardware->broadcast_accept = (uint32_t)cfg->broadcast_accept;
	eth_mac->hardware->unicast_filter_mac_low =
		((uint32_t)cfg->unicast_filter_mac[0]) |
		(((uint32_t)cfg->unicast_filter_mac[1]) << 8) |
		(((uint32_t)cfg->unicast_filter_mac[2]) << 16) |
		(((uint32_t)cfg->unicast_filter_mac[3]) << 24);
	eth_mac->hardware->unicast_filter_mac_high =
		((uint32_t)cfg->unicast_filter_mac[4]) |
		(((uint32_t)cfg->unicast_filter_mac[5]) << 8);
	eth_mac->hardware->multicast_filter_mac_0_low =
		((uint32_t)cfg->multicast_filter_mac_0[0]) |
		(((uint32_t)cfg->multicast_filter_mac_0[1]) << 8) |
		(((uint32_t)cfg->multicast_filter_mac_0[2]) << 16) |
		(((uint32_t)cfg->multicast_filter_mac_0[3]) << 24);
	eth_mac->hardware->multicast_filter_mac_0_high =
		((uint32_t)cfg->multicast_filter_mac_0[4]) |
		(((uint32_t)cfg->multicast_filter_mac_0[5]) << 8);
	eth_mac->hardware->multicast_filter_mac_1_low =
		((uint32_t)cfg->multicast_filter_mac_1[0]) |
		(((uint32_t)cfg->multicast_filter_mac_1[1]) << 8) |
		(((uint32_t)cfg->multicast_filter_mac_1[2]) << 16) |
		(((uint32_t)cfg->multicast_filter_mac_1[3]) << 24);
	eth_mac->hardware->multicast_filter_mac_1_high =
		((uint32_t)cfg->multicast_filter_mac_1[4]) |
		(((uint32_t)cfg->multicast_filter_mac_1[5]) << 8);
	eth_mac->hardware->multicast_filter_mac_2_low =
		((uint32_t)cfg->multicast_filter_mac_2[0]) |
		(((uint32_t)cfg->multicast_filter_mac_2[1]) << 8) |
		(((uint32_t)cfg->multicast_filter_mac_2[2]) << 16) |
		(((uint32_t)cfg->multicast_filter_mac_2[3]) << 24);
	eth_mac->hardware->multicast_filter_mac_2_high =
		((uint32_t)cfg->multicast_filter_mac_2[4]) |
		(((uint32_t)cfg->multicast_filter_mac_2[5]) << 8);
	eth_mac->hardware->multicast_filter_mac_3_low =
		((uint32_t)cfg->multicast_filter_mac_3[0]) |
		(((uint32_t)cfg->multicast_filter_mac_3[1]) << 8) |
		(((uint32_t)cfg->multicast_filter_mac_3[2]) << 16) |
		(((uint32_t)cfg->multicast_filter_mac_3[3]) << 24);
	eth_mac->hardware->multicast_filter_mac_3_high =
		((uint32_t)cfg->multicast_filter_mac_3[4]) |
		(((uint32_t)cfg->multicast_filter_mac_3[5]) << 8);
}

void eth_mac_notify_new_tx_dsc_created(EthMac* eth_mac){
	volatile uint32_t* LocalAddr = &(eth_mac->hardware->eth_dsc_ctrl);

	*LocalAddr = 0x00000001;
	*LocalAddr = 0x00000000;
}

void eth_mac_notify_rx_dsc_free(EthMac* eth_mac){
	volatile uint32_t* LocalAddr = &(eth_mac->hardware->eth_dsc_ctrl);

	*LocalAddr = 0x00000002;
	*LocalAddr = 0x00000000;
}

void eth_mac_start_mdio_trans(EthMac* eth_mac, uint8_t is_rd, uint8_t phy_addr, uint8_t reg_addr, uint16_t din){
	uint32_t trans_msg =
		((uint32_t)is_rd) |
		(((uint32_t)phy_addr) << 1) |
		(((uint32_t)reg_addr) << 6) |
		(((uint32_t)din) << 16);

	eth_mac->hardware->mdio_trans_ctrl = trans_msg;
}

int eth_mac_get_mdio_rdata(EthMac* eth_mac, uint16_t* rdata){
	uint32_t mdio_sts = eth_mac->hardware->mdio_trans_sts;

	if(mdio_sts & 0x00000001){
		*rdata = (uint16_t)(mdio_sts >> 16);

		return 0;
	}else{
		return -1;
	}
}

void eth_mac_set_tx_dsc(EthMac* eth_mac, uint8_t dsc_addr, EthTxDsc* tx_dsc){
	volatile uint32_t* mem_ctrl = &(eth_mac->hardware->eth_tx_dsc_mem_ctrl);

	*mem_ctrl =
		0x00000001 |
		((((uint32_t)dsc_addr) << 2) | 0x00000000) |
		(((((uint32_t)tx_dsc->frame_addr_ofs) >> 1) << 16));
	*mem_ctrl =
		0x00000001 |
		((((uint32_t)dsc_addr) << 2) | 0x00000002) |
		((((uint32_t)tx_dsc->frame_len) << 17) | 0x00010000);
}

void eth_mac_set_rx_dsc(EthMac* eth_mac, uint8_t dsc_addr, EthRxDsc* rx_dsc){
	volatile uint32_t* mem_ctrl = &(eth_mac->hardware->eth_rx_dsc_mem_ctrl);

	*mem_ctrl =
		0x00000001 |
		((((uint32_t)dsc_addr) << 2) | 0x00000000) |
		(((((uint32_t)rx_dsc->frame_addr_ofs) >> 1) << 16));
	*mem_ctrl =
		0x00000001 |
		((((uint32_t)dsc_addr) << 2) | 0x00000002) |
		0x00000000;
}

void eth_mac_get_tx_dsc(EthMac* eth_mac, uint8_t dsc_addr, EthTxDsc* tx_dsc){
	volatile uint32_t* mem_ctrl = &(eth_mac->hardware->eth_tx_dsc_mem_ctrl);
	volatile uint32_t* mem_sts = &(eth_mac->hardware->eth_tx_dsc_mem_sts);
	uint32_t rdata;

	*mem_ctrl =
		0x00000000 |
		((((uint32_t)dsc_addr) << 2) | 0x00000000);
	rdata = *mem_sts;
	tx_dsc->frame_addr_ofs = (rdata << 1);

	*mem_ctrl =
		0x00000000 |
		((((uint32_t)dsc_addr) << 2) | 0x00000002);
	rdata = *mem_sts;
	tx_dsc->is_valid = (rdata & 0x00000001) ? 0x01:0x00;
	tx_dsc->frame_len = (rdata >> 1);
}

void eth_mac_get_rx_dsc(EthMac* eth_mac, uint8_t dsc_addr, EthRxDsc* rx_dsc){
	volatile uint32_t* mem_ctrl = &(eth_mac->hardware->eth_rx_dsc_mem_ctrl);
	volatile uint32_t* mem_sts = &(eth_mac->hardware->eth_rx_dsc_mem_sts);
	uint32_t rdata;

	*mem_ctrl =
		0x00000000 |
		((((uint32_t)dsc_addr) << 2) | 0x00000000);
	rdata = *mem_sts;
	rx_dsc->frame_addr_ofs = (rdata << 1);

	*mem_ctrl =
		0x00000000 |
		((((uint32_t)dsc_addr) << 2) | 0x00000002);
	rdata = *mem_sts;
	rx_dsc->processed = (rdata & 0x00000001) ? 0x01:0x00;
	rx_dsc->frame_len = (rdata >> 1);
}

void eth_mac_enable_itr(EthMac* eth_mac, uint8_t itr_mask){
	volatile uint32_t* LocalAddr = &(eth_mac->hardware->itr_en);

	uint8_t org_itr_en = (uint8_t)((*LocalAddr) >> 8);

	org_itr_en |= itr_mask;

	eth_mac->hardware->itr_en =
		0x00000001 |
		(((uint32_t)org_itr_en) << 8);
}

void eth_mac_disable_itr(EthMac* eth_mac, uint8_t itr_mask){
	volatile uint32_t* LocalAddr = &(eth_mac->hardware->itr_en);

	uint8_t org_itr_en = (uint8_t)((*LocalAddr) >> 8);

	org_itr_en &= (~itr_mask);

	eth_mac->hardware->itr_en =
		((org_itr_en == 0x00) ? 0x00000000:0x00000001) |
		(((uint32_t)org_itr_en) << 8);
}

uint8_t eth_mac_get_itr_pending(EthMac* eth_mac){
	return (uint8_t)eth_mac->hardware->itr_pending;
}

void eth_mac_clr_itr_pending(EthMac* eth_mac, uint8_t itr_mask){
	eth_mac->hardware->itr_pending = (uint32_t)itr_mask;
}
