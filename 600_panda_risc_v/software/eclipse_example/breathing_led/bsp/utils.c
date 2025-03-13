#include <stdint.h>

#include "../include/utils.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

uint64_t get_cycle_value(){
    uint64_t cycle;
	
    cycle = read_csr(mcycle);
    cycle |= (((uint64_t)read_csr(mcycleh)) << 32);
	
    return cycle;
}

void busy_wait(uint32_t us){
    uint64_t start_t;
	uint64_t end_t;
    uint32_t count;
	
    count = us * CPU_FREQ_MHZ;
    start_t = get_cycle_value();
	end_t = start_t + count;
	
    while(get_cycle_value() < end_t);
}
