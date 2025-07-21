#include "apb_spi.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_spi_init(ApbSPI* spi, uint32_t base_addr){
	spi->hardware = (ApbSPIHd*)base_addr;
	spi->itr_en = 0x00;
	spi->trans_dire = SPI_DIRE_SEND;
	spi->trans_slave_sel = 0x00;
}

uint8_t apb_spi_tx_rx(ApbSPI* spi, uint8_t byte){
	uint32_t fifo_cs = spi->hardware->fifo_cs;
	
	if(fifo_cs & 0x00000001){
		return 0;
	}else{
		spi->hardware->fifo_cs = 0x00000002 | (((uint32_t)byte) << 8);
		
		return 1;
	}
}

void apb_spi_set_user(ApbSPI* spi, uint16_t user, uint8_t now_byte_dire, uint8_t now_byte_mul, uint8_t ss){
	spi->hardware->user = ((uint32_t)user) | (((uint32_t)ss) << 24) |
		(((uint32_t)now_byte_dire) << 16) | (((uint32_t)now_byte_mul) << 17);
}

uint8_t apb_spi_get_rev_byte(ApbSPI* spi, uint8_t* byte){
	uint32_t fifo_cs = spi->hardware->fifo_cs;
	
	if(fifo_cs & 0x00010000){
		return 0;
	}else{
		spi->hardware->fifo_cs = 0x00020000;
		
		*byte = (uint8_t)(spi->hardware->fifo_cs >> 24);
		
		return 1;
	}
}

// 设置传输方向(仅std模式可用)
void apb_spi_set_direction(ApbSPI* spi, uint8_t dire){
	spi->trans_dire = dire;
	
	spi->hardware->trans_params = ((uint32_t)spi->trans_dire) | (((uint32_t)spi->trans_slave_sel) << 8);
}

void apb_spi_set_slave_sel(ApbSPI* spi, uint8_t slave_sel){
	spi->trans_slave_sel = slave_sel;
	
	spi->hardware->trans_params = ((uint32_t)spi->trans_dire) | (((uint32_t)spi->trans_slave_sel) << 8);
}

void apb_spi_enable_itr(ApbSPI* spi, uint8_t itr_en, uint16_t tx_rx_bytes_n_th){
	spi->itr_en = (((uint16_t)itr_en) << 8) | 0x0001;
	
	spi->hardware->itr_status_en = spi->itr_en;
	spi->hardware->tx_rx_itr_th = tx_rx_bytes_n_th - 1;
}

void apb_spi_set_tx_rx_bytes_n_th(ApbSPI* spi, uint16_t tx_rx_bytes_n_th){
	spi->hardware->tx_rx_itr_th = tx_rx_bytes_n_th - 1;
}

void apb_spi_disable_itr(ApbSPI* spi){
	spi->itr_en = 0x0000;
	
	spi->hardware->itr_status_en = spi->itr_en;
}

uint8_t apb_spi_get_itr_status(ApbSPI* spi){
	uint32_t itr_status_en = spi->hardware->itr_status_en;
	
	return (uint8_t)(itr_status_en >> 24);
}

void apb_spi_clear_itr_flag(ApbSPI* spi){
	spi->hardware->itr_status_en = (uint32_t)spi->itr_en;
}

void apb_spi_set_xip(ApbSPI* spi, uint8_t en_xip){
	spi->hardware->xip = en_xip;
}
