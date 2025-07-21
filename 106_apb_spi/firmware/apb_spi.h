#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// SPI传输方向
#define SPI_DIRE_SEND_REV 0x03
#define SPI_DIRE_SEND 0x01
#define SPI_DIRE_REV 0x02
// 当前byte的传输方向(仅dual/quad模式可用)
#define SPI_NOW_BYTE_SEND 0x01
#define SPI_NOW_BYTE_REV 0x00
// 当前byte是否在多端口上传输
#define SPI_NOW_BYTE_ENABLE_MUL 0x01
#define SPI_NOW_BYTE_DISABLE_MUL 0x00

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __APB_SPI_H
#define __APB_SPI_H

typedef struct{
	uint32_t fifo_cs;
	uint32_t itr_status_en;
	uint32_t tx_rx_itr_th;
	uint32_t trans_params;
	uint32_t user;
	uint32_t xip;
}ApbSPIHd;

typedef struct{
	ApbSPIHd* hardware;
	uint16_t itr_en;
	uint8_t trans_dire;
	uint8_t trans_slave_sel;
}ApbSPI;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_spi_init(ApbSPI* spi, uint32_t base_addr);

uint8_t apb_spi_tx_rx(ApbSPI* spi, uint8_t byte);
void apb_spi_set_user(ApbSPI* spi, uint16_t user, uint8_t now_byte_dire, uint8_t now_byte_mul, uint8_t ss);
uint8_t apb_spi_get_rev_byte(ApbSPI* spi, uint8_t* byte);
void apb_spi_set_direction(ApbSPI* spi, uint8_t dire);
void apb_spi_set_slave_sel(ApbSPI* spi, uint8_t slave_sel);

void apb_spi_enable_itr(ApbSPI* spi, uint8_t itr_en, uint16_t tx_rx_bytes_n_th);
void apb_spi_set_tx_rx_bytes_n_th(ApbSPI* spi, uint16_t tx_rx_bytes_n_th);
void apb_spi_disable_itr(ApbSPI* spi);
uint8_t apb_spi_get_itr_status(ApbSPI* spi);
void apb_spi_clear_itr_flag(ApbSPI* spi);

void apb_spi_set_xip(ApbSPI* spi, uint8_t en_xip);
