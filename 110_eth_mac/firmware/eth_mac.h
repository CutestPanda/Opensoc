#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 中断掩码
#define ETH_DMA_MM2S_CMD_DONE_ITR_MASK 0x01
#define ETH_DMA_S2MM_CMD_DONE_ITR_MASK 0x02
#define ETH_ALL_ITR_MASK 0x03

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __ETH_MAC_H

typedef struct{
	uint32_t eth_dsc_ctrl;
	uint32_t eth_const_sts;
	uint32_t eth_tx_buf_baseaddr;
	uint32_t eth_dsc_buf_len;
	uint32_t eth_rx_buf_baseaddr;
	uint32_t mdc_div_rate;
	uint32_t broadcast_accept;
	uint32_t unicast_filter_mac_low;
	uint32_t unicast_filter_mac_high;
	uint32_t multicast_filter_mac_0_low;
	uint32_t multicast_filter_mac_0_high;
	uint32_t multicast_filter_mac_1_low;
	uint32_t multicast_filter_mac_1_high;
	uint32_t multicast_filter_mac_2_low;
	uint32_t multicast_filter_mac_2_high;
	uint32_t multicast_filter_mac_3_low;
	uint32_t multicast_filter_mac_3_high;
	uint32_t mdio_trans_ctrl;
	uint32_t mdio_trans_sts;
	uint32_t eth_tx_dsc_mem_ctrl;
	uint32_t eth_tx_dsc_mem_sts;
	uint32_t eth_rx_dsc_mem_ctrl;
	uint32_t eth_rx_dsc_mem_sts;
	uint32_t itr_en;
	uint32_t itr_pending;
}EthMacHd;

typedef struct{
	EthMacHd* hardware;
}EthMac;

typedef struct{
	uint32_t eth_tx_buf_baseaddr;
	uint8_t eth_tx_dsc_buf_len;
	uint32_t eth_rx_buf_baseaddr;
	uint8_t eth_rx_dsc_buf_len;
	uint32_t mdc_div_rate;
	uint8_t broadcast_accept;
	uint8_t unicast_filter_mac[6];
	uint8_t multicast_filter_mac_0[6];
	uint8_t multicast_filter_mac_1[6];
	uint8_t multicast_filter_mac_2[6];
	uint8_t multicast_filter_mac_3[6];
}EthMacCfg;

typedef struct{
	uint16_t frame_len;
	uint16_t frame_addr_ofs;
	uint8_t is_valid;
}EthTxDsc;

typedef struct{
	uint16_t frame_len;
	uint16_t frame_addr_ofs;
	uint8_t processed;
}EthRxDsc;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void init_eth_mac(EthMac* eth_mac, uint32_t baseaddr);
void cfg_eth_mac(EthMac* eth_mac, const EthMacCfg* cfg);

void eth_mac_notify_new_tx_dsc_created(EthMac* eth_mac);
void eth_mac_notify_rx_dsc_free(EthMac* eth_mac);

void eth_mac_start_mdio_trans(EthMac* eth_mac, uint8_t is_rd, uint8_t phy_addr, uint8_t reg_addr, uint16_t din);
int eth_mac_get_mdio_rdata(EthMac* eth_mac, uint16_t* rdata);

void eth_mac_set_tx_dsc(EthMac* eth_mac, uint8_t dsc_addr, EthTxDsc* tx_dsc);
void eth_mac_set_rx_dsc(EthMac* eth_mac, uint8_t dsc_addr, EthRxDsc* rx_dsc);
void eth_mac_get_tx_dsc(EthMac* eth_mac, uint8_t dsc_addr, EthTxDsc* tx_dsc);
void eth_mac_get_rx_dsc(EthMac* eth_mac, uint8_t dsc_addr, EthRxDsc* rx_dsc);

void eth_mac_enable_itr(EthMac* eth_mac, uint8_t itr_mask);
void eth_mac_disable_itr(EthMac* eth_mac, uint8_t itr_mask);
uint8_t eth_mac_get_itr_pending(EthMac* eth_mac);
void eth_mac_clr_itr_pending(EthMac* eth_mac, uint8_t itr_mask);
