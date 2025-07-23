#include <stdint.h>

#include "../include/utils.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

uint64_t get_cycle_value(){
    uint64_t cycle;
	
    cycle = read_csr(mcycle);
    cycle += (uint64_t)(read_csr(mcycleh)) << 32;
	
    return cycle;
}

void busy_wait(uint32_t us){
    uint64_t tmp;
    uint32_t count;
	
	uint32_t old_mie = read_csr(mie);
	
	write_csr(mie, 0x00000000);
	
    count = us * CPU_FREQ_MHZ;
    tmp = get_cycle_value();
	
    while (get_cycle_value() < (tmp + count));
	
	write_csr(mie, old_mie);
}
