#include "apb_sdio.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define SDIO_DIV_RATE_INIT_V 199 // 初始的SDIO时钟分频数

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_sdio_init(ApbSDIO* sdio, uint32_t base_addr){
	sdio->hardware = (ApbSDIOHd*)base_addr;
	
	sdio->en_sdio_clk = 0;
	sdio->en_wide_sdio = 0;
	sdio->sdio_div_rate = SDIO_DIV_RATE_INIT_V;
}

void apb_sdio_set_en_clk(ApbSDIO* sdio, uint8_t en_sdio_clk){
	sdio->en_sdio_clk = en_sdio_clk;
	
	sdio->hardware->ctrler_cs = (((uint32_t)en_sdio_clk) << 16) | 
		(((uint32_t)sdio->en_wide_sdio) << 17) |
		(((uint32_t)sdio->sdio_div_rate) << 18);
}

void apb_sdio_set_en_wide_sdio(ApbSDIO* sdio, uint8_t en_wide_sdio){
	sdio->en_wide_sdio = en_wide_sdio;
	
	sdio->hardware->ctrler_cs = (((uint32_t)sdio->en_sdio_clk) << 16) |
		(((uint32_t)en_wide_sdio) << 17) |
		(((uint32_t)sdio->sdio_div_rate) << 18);
}

void apb_sdio_set_div_rate(ApbSDIO* sdio, uint16_t div_rate){
	sdio->sdio_div_rate = div_rate;
	
	sdio->hardware->ctrler_cs = (((uint32_t)sdio->en_sdio_clk) << 16) |
		(((uint32_t)sdio->en_wide_sdio) << 17) |
		(((uint32_t)div_rate) << 18);
}

void apb_sdio_get_resp(ApbSDIO* sdio, ApbSDIOResp* resp){
	uint32_t resp_field0_sts = sdio->hardware->resp_field0_sts;
	
	resp->is_long_resp = (resp_field0_sts >> 24) & 0x00000001;
	resp->crc_err = (resp_field0_sts >> 25) & 0x00000001;
	resp->is_timeout = (resp_field0_sts >> 26) & 0x00000001;
	
	resp->resp_content[0] = resp_field0_sts & 0x00FFFFFF;
	resp->resp_content[1] = sdio->hardware->resp_field1;
	if(resp->is_long_resp){
		resp->resp_content[2] = sdio->hardware->resp_field2;
		resp->resp_content[3] = sdio->hardware->resp_field3;
	}else{
		resp->resp_content[1] = resp->resp_content[1] & 0x00003FFF;
	}
}

void apb_sdio_enable_itr(ApbSDIO* sdio, uint8_t itr_en){
	sdio->hardware->itr_en = ((uint32_t)itr_en << 8) | 0x00000001;
}

void apb_sdio_disable_itr(ApbSDIO* sdio){
	sdio->hardware->itr_en = 0x00000000;
}

int apb_sdio_wt_cmd(ApbSDIO* sdio, uint8_t cmd_id, uint32_t cmd_par, uint8_t rw_n){
	if(sdio->hardware->fifo_sts & 0x00000001){
		return -1;
	}else{
		sdio->hardware->cmd_par = cmd_par;
		sdio->hardware->cmd_id_rw_n = ((uint32_t)cmd_id) | (((uint32_t)rw_n) << 8);
		
		return 0;
	}
}

int apb_sdio_read_data(ApbSDIO* sdio, uint32_t* rdata){
	if(sdio->hardware->fifo_sts & 0x00000002){
		return -1;
	}else{
		(*rdata) = sdio->hardware->rdata;
		
		return 0;
	}
}

int apb_sdio_wt_data(ApbSDIO* sdio, uint32_t wdata){
	if(sdio->hardware->fifo_sts & 0x00000004){
		return -1;
	}else{
		sdio->hardware->wdata = wdata;
		
		return 0;
	}
}
