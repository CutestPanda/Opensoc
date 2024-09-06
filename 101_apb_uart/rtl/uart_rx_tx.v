`timescale 1ns / 1ps
/********************************************************************
��ģ��: UART������

����: 
ʹ�÷���/����fifo��UART������
��ѡAXIS�ӿڻ�FIFO�ӿ�

ע�⣺
��ʹ��FIFO�ӿ�ʱ, UART����FIFO��ʹ�ñ�׼FIFO
UART���տ������

Э��:
AXIS MASTER/SLAVE
FIFO READ/WRITE
UART

����: �¼�ҫ
����: 2023/11/08
********************************************************************/


module uart_rx_tx #(
    parameter integer clk_frequency_MHz = 200, // ʱ��Ƶ��
    parameter integer baud_rate = 115200, // ������
    parameter interface = "fifo", // �ӿ�Э��(axis|fifo)
    parameter real simulation_delay = 1 // ������ʱ
)(
    input wire clk,
    input wire resetn,
    
    input wire rx,
    output wire tx,
    
    output wire[7:0] m_axis_rx_byte_data,
    output wire m_axis_rx_byte_valid,
    input wire m_axis_rx_byte_ready,
    
    output wire[7:0] rx_buf_fifo_din,
    output wire rx_buf_fifo_wen,
    input wire rx_buf_fifo_full,
    
    input wire[7:0] s_axis_tx_byte_data,
    input wire s_axis_tx_byte_valid,
    output wire s_axis_tx_byte_ready,
    
    input wire[7:0] tx_buf_fifo_dout,
    input wire tx_buf_fifo_empty,
    input wire tx_buf_fifo_almost_empty,
    output wire tx_buf_fifo_ren,
    
    output wire rx_err,
    output wire tx_idle,
    output wire rx_idle,
    output wire tx_done,
    output wire rx_done,
    output wire rx_start
);
    
    // �����ջ������Ƿ����
    reg rx_err_reg;
    
    assign rx_err = rx_err_reg;
    
    always @(posedge clk or negedge resetn)
    begin
        if(~resetn)
            rx_err_reg <= 1'b0;
        else
            # simulation_delay rx_err_reg <= (interface == "axis") ? (m_axis_rx_byte_valid & (~m_axis_rx_byte_ready)):(rx_buf_fifo_wen & rx_buf_fifo_full);
    end
    
    /** uart�շ� **/
    localparam integer clk_frequency = clk_frequency_MHz * 1000000;
    
    assign rx_buf_fifo_din = m_axis_rx_byte_data;
    assign rx_buf_fifo_wen = m_axis_rx_byte_valid;
    
    uart_rx #(
        .clk_frequency(clk_frequency),
        .baud_rate(baud_rate),
        .simulation_delay(simulation_delay)
    )uart_rx_u(
        .clk(clk),
        .rst_n(resetn),
        .rx(rx),
        .rx_byte_data(m_axis_rx_byte_data),
        .rx_byte_valid(m_axis_rx_byte_valid),
        .rx_byte_ready((interface == "axis") ? m_axis_rx_byte_ready:(~rx_buf_fifo_full)),
        .rx_idle(rx_idle),
        .rx_done(rx_done),
        .rx_start(rx_start)
    );
    
    uart_tx #(
        .clk_frequency(clk_frequency),
        .baud_rate(baud_rate),
        .interface(interface),
        .simulation_delay(simulation_delay)
    )uart_tx_u(
        .clk(clk),    
        .rst_n(resetn),
        .tx(tx),
        .tx_byte_data(s_axis_tx_byte_data),
        .tx_byte_valid(s_axis_tx_byte_valid),
        .tx_byte_ready(s_axis_tx_byte_ready),
        .tx_fifo_dout(tx_buf_fifo_dout),
        .tx_fifo_empty(tx_buf_fifo_empty),
        .tx_fifo_ren(tx_buf_fifo_ren),
        .tx_idle(tx_idle),
        .tx_done(tx_done)
    );

endmodule
