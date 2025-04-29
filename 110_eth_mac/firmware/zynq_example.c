#include "gic.h"
#include "eth_mac.h"

#include "xil_printf.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define ETH_TX_DSC_N 8 // 以太网发送描述符个数
#define ETH_RX_DSC_N 8 // 以太网接收描述符个数

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static void eth_mac_dma_mm2s_cmd_done_itr_handler(void* callback_ref);
static void eth_mac_dma_s2mm_cmd_done_itr_handler(void* callback_ref);

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static XScuGic gic;
static EthMac eth_mac;

static uint32_t eth_tx_buf[16][2048 / 4];
static uint32_t eth_rx_buf[16][2048 / 4];

static uint16_t eth_mac_dma_s2mm_cmd_done_cnt = 0;
static uint16_t eth_recv_n = 0;
static uint8_t eth_rx_dsc_id = 0;

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(){
	// 初始化GIC
	if(init_gic(&gic, XPAR_SCUGIC_SINGLE_DEVICE_ID)){
		return XST_FAILURE;
	}
	
	// 初始化ETH
	init_eth_mac(&eth_mac, XPAR_AXI_ETH_MAC_0_BASEADDR);

	// 设置ETH接收描述符
	EthRxDsc eth_rx_dsc;

	for(int i = 0;i < ETH_RX_DSC_N;i++){
		eth_rx_dsc.frame_addr_ofs = i * 2048;
		eth_mac_set_rx_dsc(&eth_mac, i, &eth_rx_dsc);
	}

	// 配置ETH运行时参数
	EthMacCfg eth_cfg;

	eth_cfg.eth_tx_buf_baseaddr = (uint32_t)eth_tx_buf[0];
	eth_cfg.eth_tx_dsc_buf_len = ETH_TX_DSC_N - 1;
	eth_cfg.eth_rx_buf_baseaddr = (uint32_t)eth_rx_buf[0];
	eth_cfg.eth_rx_dsc_buf_len = ETH_RX_DSC_N - 1;
	eth_cfg.mdc_div_rate = 49;
	eth_cfg.broadcast_accept = 0x00;
	eth_cfg.unicast_filter_mac[0] = 0x55;
	eth_cfg.unicast_filter_mac[1] = 0x44;
	eth_cfg.unicast_filter_mac[2] = 0x33;
	eth_cfg.unicast_filter_mac[3] = 0x22;
	eth_cfg.unicast_filter_mac[4] = 0x11;
	eth_cfg.unicast_filter_mac[5] = 0x00;
	eth_cfg.multicast_filter_mac_0[0] = 0x00;
	eth_cfg.multicast_filter_mac_0[1] = 0x00;
	eth_cfg.multicast_filter_mac_0[2] = 0x00;
	eth_cfg.multicast_filter_mac_0[3] = 0x00;
	eth_cfg.multicast_filter_mac_0[4] = 0x00;
	eth_cfg.multicast_filter_mac_0[5] = 0x00;
	eth_cfg.multicast_filter_mac_1[0] = 0x00;
	eth_cfg.multicast_filter_mac_1[1] = 0x00;
	eth_cfg.multicast_filter_mac_1[2] = 0x00;
	eth_cfg.multicast_filter_mac_1[3] = 0x00;
	eth_cfg.multicast_filter_mac_1[4] = 0x00;
	eth_cfg.multicast_filter_mac_1[5] = 0x00;
	eth_cfg.multicast_filter_mac_2[0] = 0x00;
	eth_cfg.multicast_filter_mac_2[1] = 0x00;
	eth_cfg.multicast_filter_mac_2[2] = 0x00;
	eth_cfg.multicast_filter_mac_2[3] = 0x00;
	eth_cfg.multicast_filter_mac_2[4] = 0x00;
	eth_cfg.multicast_filter_mac_2[5] = 0x00;
	eth_cfg.multicast_filter_mac_3[0] = 0x00;
	eth_cfg.multicast_filter_mac_3[1] = 0x00;
	eth_cfg.multicast_filter_mac_3[2] = 0x00;
	eth_cfg.multicast_filter_mac_3[3] = 0x00;
	eth_cfg.multicast_filter_mac_3[4] = 0x00;
	eth_cfg.multicast_filter_mac_3[5] = 0x00;

	cfg_eth_mac(&eth_mac, &eth_cfg);

	// 配置ETH中断
	eth_mac_enable_itr(&eth_mac, ETH_DMA_S2MM_CMD_DONE_ITR_MASK);

	if(gic_conn_config_itr(&gic, NULL, eth_mac_dma_mm2s_cmd_done_itr_handler, XPAR_FABRIC_AXI_ETH_MAC_0_DMA_MM2S_CMD_DONE_ITR_INTR,
		20, ITR_RISING_EDGE_TG)){
		return XST_FAILURE;
	}

	if(gic_conn_config_itr(&gic, NULL, eth_mac_dma_s2mm_cmd_done_itr_handler, XPAR_FABRIC_AXI_ETH_MAC_0_DMA_S2MM_CMD_DONE_ITR_INTR,
		20, ITR_RISING_EDGE_TG)){
		return XST_FAILURE;
	}

	// 设置ETH发送描述符
	EthTxDsc eth_tx_dsc;

	eth_tx_dsc.frame_addr_ofs = 0;
	eth_tx_dsc.frame_len = 14 + 28;

	eth_mac_set_tx_dsc(&eth_mac, 0, &eth_tx_dsc);

	// 生成ARP请求帧
	uint8_t* eth_tx_frame_ptr = (uint8_t*)eth_tx_buf[0];

	eth_tx_frame_ptr[0] = 0xff;
	eth_tx_frame_ptr[1] = 0xff;
	eth_tx_frame_ptr[2] = 0xff;
	eth_tx_frame_ptr[3] = 0xff;
	eth_tx_frame_ptr[4] = 0xff;
	eth_tx_frame_ptr[5] = 0xff;
	eth_tx_frame_ptr[6] = 0x00;
	eth_tx_frame_ptr[7] = 0x11;
	eth_tx_frame_ptr[8] = 0x22;
	eth_tx_frame_ptr[9] = 0x33;
	eth_tx_frame_ptr[10] = 0x44;
	eth_tx_frame_ptr[11] = 0x55;
	eth_tx_frame_ptr[12] = 0x08;
	eth_tx_frame_ptr[13] = 0x06;
	eth_tx_frame_ptr[14] = 0x00;
	eth_tx_frame_ptr[15] = 0x01;
	eth_tx_frame_ptr[16] = 0x08;
	eth_tx_frame_ptr[17] = 0x00;
	eth_tx_frame_ptr[18] = 0x06;
	eth_tx_frame_ptr[19] = 0x04;
	eth_tx_frame_ptr[20] = 0x00;
	eth_tx_frame_ptr[21] = 0x01;
	eth_tx_frame_ptr[22] = 0x00;
	eth_tx_frame_ptr[23] = 0x11;
	eth_tx_frame_ptr[24] = 0x22;
	eth_tx_frame_ptr[25] = 0x33;
	eth_tx_frame_ptr[26] = 0x44;
	eth_tx_frame_ptr[27] = 0x55;

	// 源IP地址 = 192.168.1.109
	eth_tx_frame_ptr[28] = 0xc0;
	eth_tx_frame_ptr[29] = 0xa8;
	eth_tx_frame_ptr[30] = 0x01;
	eth_tx_frame_ptr[31] = 0x6d;

	eth_tx_frame_ptr[32] = 0xff;
	eth_tx_frame_ptr[33] = 0xff;
	eth_tx_frame_ptr[34] = 0xff;
	eth_tx_frame_ptr[35] = 0xff;
	eth_tx_frame_ptr[36] = 0xff;
	eth_tx_frame_ptr[37] = 0xff;

	// 目标IP地址 = 192.168.1.102
	eth_tx_frame_ptr[38] = 0xc0;
	eth_tx_frame_ptr[39] = 0xa8;
	eth_tx_frame_ptr[40] = 0x01;
	eth_tx_frame_ptr[41] = 0x66;

	// 向ETH提交一个发送描述符
	eth_mac_notify_new_tx_dsc_created(&eth_mac);

	while(1){
		if(eth_mac_dma_s2mm_cmd_done_cnt){
			// 读取接收描述符
			EthRxDsc rx_dsc;

			eth_mac_get_rx_dsc(&eth_mac, eth_rx_dsc_id, &rx_dsc);

			xil_printf("eth_rx len = %d\r\n", rx_dsc.frame_len);

			// 对ETH释放一个接收描述符
			eth_mac_notify_rx_dsc_free(&eth_mac);

			if(eth_rx_dsc_id == (ETH_RX_DSC_N - 1)){
				eth_rx_dsc_id = 0;
			}else{
				eth_rx_dsc_id++;
			}

			eth_mac_dma_s2mm_cmd_done_cnt--;
			eth_recv_n++;
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static void eth_mac_dma_mm2s_cmd_done_itr_handler(void* callback_ref){
	eth_mac_clr_itr_pending(&eth_mac, ETH_DMA_MM2S_CMD_DONE_ITR_MASK);
}

static void eth_mac_dma_s2mm_cmd_done_itr_handler(void* callback_ref){
	eth_mac_dma_s2mm_cmd_done_cnt++;

	eth_mac_clr_itr_pending(&eth_mac, ETH_DMA_S2MM_CMD_DONE_ITR_MASK);
}
