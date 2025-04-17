`timescale 1ns / 1ps

class ICBTrans #(
	integer addr_width = 32, // 地址位宽
	integer data_width = 32 // 数据位宽
);
	
	bit[addr_width-1:0] cmd_addr;
	bit cmd_read;
	bit[data_width-1:0] cmd_wdata;
	bit[data_width/8-1:0] cmd_wmask;
	
	bit[data_width-1:0] rsp_rdata;
	bit rsp_err;
	
endclass

module s_icb_memory_map_model #(
	parameter real out_drive_t = 1, // 输出驱动延迟量
    parameter integer addr_width = 32, // 地址位宽(1~64)
    parameter integer data_width = 32, // 数据位宽(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter integer memory_map_depth = 1024 * 64 // 存储映射深度(以字节计)
)(
	ICB.slave s_icb_if
);
	
	bit[data_width-1:0] mem[0:memory_map_depth-1];
	
	ICBTrans #(.addr_width(addr_width), .data_width(data_width)) icb_cmd_trans_fifo[$];
	
	initial
	begin
		s_icb_if.cb_slave.cmd_ready <= 1'b0;
		
		forever
		begin
			automatic int unsigned wait_n;
			automatic ICBTrans #(.addr_width(addr_width), .data_width(data_width)) icb_cmd_trans;
			
			wait(icb_cmd_trans_fifo.size() < 8);
			
			wait_n = $urandom_range(0, 3);
			
			repeat(wait_n)
				@(posedge s_icb_if.clk iff s_icb_if.rst_n);
			
			s_icb_if.cb_slave.cmd_ready <= 1'b1;
			
			do
			begin
				@(posedge s_icb_if.clk iff s_icb_if.rst_n);
			end
			while(!(s_icb_if.cmd_valid & s_icb_if.cmd_ready));
			
			icb_cmd_trans = new();
			icb_cmd_trans.cmd_addr = s_icb_if.cmd_addr;
			icb_cmd_trans.cmd_read = s_icb_if.cmd_read;
			icb_cmd_trans.cmd_wdata = s_icb_if.cmd_wdata;
			icb_cmd_trans.cmd_wmask = s_icb_if.cmd_wmask;
			
			icb_cmd_trans_fifo.push_back(icb_cmd_trans);
			
			s_icb_if.cb_slave.cmd_ready <= 1'b0;
		end
	end
	
	initial
	begin
		s_icb_if.cb_slave.rsp_rdata <= {data_width{1'bx}};
		s_icb_if.cb_slave.rsp_err <= 1'bx;
		s_icb_if.cb_slave.rsp_valid <= 1'b0;
		
		forever
		begin
			automatic int unsigned wait_n;
			automatic ICBTrans #(.addr_width(addr_width), .data_width(data_width)) icb_cmd_trans;
			
			wait(icb_cmd_trans_fifo.size() != 0);
			
			icb_cmd_trans = icb_cmd_trans_fifo.pop_front();
			wait_n = $urandom_range(0, 3);
			
			repeat(wait_n)
				@(posedge s_icb_if.clk iff s_icb_if.rst_n);
			
			s_icb_if.cb_slave.rsp_rdata <= 
				icb_cmd_trans.cmd_read ? 
					mem[icb_cmd_trans.cmd_addr / (data_width / 8)]:
					{data_width{1'bx}};
			s_icb_if.cb_slave.rsp_err <= 1'b0;
			s_icb_if.cb_slave.rsp_valid <= 1'b1;
			
			if(!icb_cmd_trans.cmd_read)
			begin
				automatic bit[data_width-1:0] org_wdata = mem[icb_cmd_trans.cmd_addr / (data_width / 8)];
				automatic bit[data_width-1:0] new_wdata = icb_cmd_trans.cmd_wdata;
				automatic bit[data_width-1:0] real_wdata = 0;
				
				for(int i = 0;i < data_width/8;i++)
				begin
					real_wdata >>= 8;
					
					if(icb_cmd_trans.cmd_wmask[i])
						real_wdata[data_width-1:data_width-8] = new_wdata[7:0];
					else
						real_wdata[data_width-1:data_width-8] = org_wdata[7:0];
					
					new_wdata >>= 8;
					org_wdata >>= 8;
				end
				
				mem[icb_cmd_trans.cmd_addr / (data_width / 8)] = real_wdata;
			end
			
			do
			begin
				@(posedge s_icb_if.clk iff s_icb_if.rst_n);
			end
			while(!(s_icb_if.rsp_valid & s_icb_if.rsp_ready));
			
			s_icb_if.cb_slave.rsp_rdata <= {data_width{1'bx}};
			s_icb_if.cb_slave.rsp_err <= 1'bx;
			s_icb_if.cb_slave.rsp_valid <= 1'b0;
		end
	end
	
endmodule
