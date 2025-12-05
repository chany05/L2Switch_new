`timescale 1ps / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/25 10:00:00
// Module Name: L2_Switch
// Description: 4-Port L2 Switch with Self-Learning and Cut-Through
//////////////////////////////////////////////////////////////////////////////////

// Include the file containing RX_Unit and TX_Unit
//`include "EndDevice.v"

//================================================================
// Simple FIFO Buffer
//================================================================
module Simple_FIFO #(
    parameter DATA_WIDTH = 16,
    parameter FIFO_DEPTH = 8
)(
    input clk,
    input rst,
    input flush,  // FIFO 초기화 신호
    // Write Port
    input wr_en,
    input [DATA_WIDTH-1:0] wr_data,
    output full,
    // Read Port
    input rd_en,
    output [DATA_WIDTH-1:0] rd_data,
    output empty
);
    localparam ADDR_WIDTH = $clog2(FIFO_DEPTH);

    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];
    reg [ADDR_WIDTH:0] wr_ptr, rd_ptr;
    reg [ADDR_WIDTH:0] count;

    assign full = (count == FIFO_DEPTH);
    assign empty = (count == 0);
    assign rd_data = mem[rd_ptr[ADDR_WIDTH-1:0]];

    always @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count <= 0;
        end else begin
            if (wr_en && !full) begin
                mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1;
            end
            if (rd_en && !empty) begin
                rd_ptr <= rd_ptr + 1;
            end

            if (wr_en && !full && !(rd_en && !empty)) begin
                count <= count + 1;
            end else if (!wr_en && (rd_en && !empty)) begin
                count <= count - 1;
            end
        end
    end
endmodule


//================================================================
// Switch Port: RX, TX, FIFO를 하나로 묶은 포트 모듈
//================================================================
module Switch_Port #(
    parameter DEPTH = 16,
    parameter ADDR_WIDTH = 4,
    parameter FIFO_DEPTH = 8
)(
    input clk,
    input rst,
    input fifo_flush,  // FIFO 초기화 신호
    
    // 외부 물리적 연결
    input rx_bit_in,
    output tx_bit_out,

    // 스위치 코어 로직과의 연결
    output [DEPTH-1:0] rx_frame_out,
    output frame_rx_valid_out,
    input fifo_wr_en_in,
    input [DEPTH-1:0] fifo_wr_data_in
);
    // FIFO와 TX Unit 연결을 위한 내부 신호
    wire [DEPTH-1:0] fifo_rd_data;
    wire fifo_empty;
    wire tx_busy;  // TX Unit busy 신호
    reg [DEPTH-1:0] tx_frame_to_unit;
    reg frame_tx_valid_to_unit;

    // 1. RX Unit 인스턴스화
    RX_Unit #(
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .MAC_ADDRESS({ADDR_WIDTH{1'b1}}) // 스위치 포트의 RX는 모든 프레임을 받음
    ) u_rx_unit (
        .clk(clk), .rst(rst),
        .rx_bit(rx_bit_in),
        .rx_frame(rx_frame_out),
        .frame_rx_valid(frame_rx_valid_out),
        .rx_data_out()
    );

    // 2. Output FIFO 인스턴스화
    Simple_FIFO #(
        .DATA_WIDTH(DEPTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_fifo (
        .clk(clk), .rst(rst),
        .flush(fifo_flush),
        .wr_en(fifo_wr_en_in),
        .wr_data(fifo_wr_data_in),
        .full(),
        .rd_en(!fifo_empty && !tx_busy && !frame_tx_valid_to_unit),  // TX 완료 후에만 읽기
        .rd_data(fifo_rd_data),
        .empty(fifo_empty)
    );

    // 3. TX Unit 인스턴스화
    TX_Unit #(
        .DEPTH(DEPTH)
    ) u_tx_unit (
        .clk(clk), .rst(rst),
        .tx_frame(tx_frame_to_unit),
        .frame_tx_valid(frame_tx_valid_to_unit),
        .tx_bit(tx_bit_out),
        .tx_busy(tx_busy)
    );

    // FIFO에서 데이터를 읽어 TX Unit으로 전달하는 로직
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_frame_to_unit <= 0;
            frame_tx_valid_to_unit <= 0;
        end else begin
            frame_tx_valid_to_unit <= 0; // 기본적으로 0으로 유지
            // TX가 idle 상태이고 FIFO에 데이터가 있으면 전송
            if (!fifo_empty && !tx_busy && !frame_tx_valid_to_unit) begin
                tx_frame_to_unit <= fifo_rd_data;
                frame_tx_valid_to_unit <= 1;
            end
        end
    end
endmodule

//================================================================
// L2 Switch Main Module (Round-Robin Scheduling)
//================================================================
module L2_Switch #(
    parameter NUM_PORTS = 4,
    parameter DEPTH = 16,
    parameter ADDR_WIDTH = 4,
    parameter TABLE_SIZE = 16,
    parameter FIFO_DEPTH = 8
)(
    input clk,
    input rst,
    input clear_fifos,  // 모든 FIFO 초기화 신호
    input [NUM_PORTS-1:0] rx_bit_in,
    output [NUM_PORTS-1:0] tx_bit_out
);

    // Frame Structure Constants
    localparam SFD_WIDTH = 4;
    localparam DEST_ADDR_MSB = DEPTH - SFD_WIDTH - 1;
    localparam DEST_ADDR_LSB = DEPTH - SFD_WIDTH - ADDR_WIDTH;
    localparam SRC_ADDR_MSB = DEST_ADDR_LSB - 1;
    localparam SRC_ADDR_LSB = DEST_ADDR_LSB - ADDR_WIDTH;
    localparam BROADCAST_ADDR = {ADDR_WIDTH{1'b1}};

    // Internal signals for RX units
    wire [DEPTH-1:0] rx_frame [0:NUM_PORTS-1];
    wire frame_rx_valid [0:NUM_PORTS-1];

    // MAC Address Table
    reg [ADDR_WIDTH-1:0] mac_table_addr [0:TABLE_SIZE-1];
    reg [$clog2(NUM_PORTS)-1:0] mac_table_port [0:TABLE_SIZE-1];
    reg mac_table_valid [0:TABLE_SIZE-1];
    reg [$clog2(TABLE_SIZE)-1:0] mac_table_next_idx;

    // FIFO interface signals
    reg fifo_wr_en [0:NUM_PORTS-1];
    reg [DEPTH-1:0] fifo_wr_data [0:NUM_PORTS-1];

    // ============================================================
    // Round-Robin Scheduler 관련 신호
    // ============================================================
    reg [$clog2(NUM_PORTS)-1:0] rr_current_port;  // 현재 처리 중인 포트
    
    // 각 포트별 입력 큐 (수신된 프레임 저장)
    reg [DEPTH-1:0] input_queue [0:NUM_PORTS-1];
    reg input_queue_valid [0:NUM_PORTS-1];
    
    // 포워딩 상태 머신
    localparam S_IDLE = 2'd0;
    localparam S_LOOKUP = 2'd1;
    localparam S_FORWARD = 2'd2;
    localparam S_FLOOD = 2'd3;
    
    reg [1:0] fwd_state;
    reg [DEPTH-1:0] current_frame;
    reg [$clog2(NUM_PORTS)-1:0] current_src_port;
    reg [ADDR_WIDTH-1:0] current_dest_mac;
    reg [ADDR_WIDTH-1:0] current_src_mac;
    reg [$clog2(NUM_PORTS)-1:0] flood_port_idx;  // Flooding 시 현재 처리 중인 포트
    reg [$clog2(NUM_PORTS)-1:0] dest_port_reg;
    reg dest_found_reg;

    integer i, j;

    // Generate RX, FIFO, TX units for each port
    genvar port_idx;
    generate
        for (port_idx = 0; port_idx < NUM_PORTS; port_idx = port_idx + 1) begin : port_inst
            Switch_Port #(
                .DEPTH(DEPTH),
                .ADDR_WIDTH(ADDR_WIDTH),
                .FIFO_DEPTH(FIFO_DEPTH)
            ) u_switch_port (
                .clk(clk), .rst(rst),
                .fifo_flush(clear_fifos),
                .rx_bit_in(rx_bit_in[port_idx]),
                .tx_bit_out(tx_bit_out[port_idx]),
                .rx_frame_out(rx_frame[port_idx]),
                .frame_rx_valid_out(frame_rx_valid[port_idx]),
                .fifo_wr_en_in(fifo_wr_en[port_idx]),
                .fifo_wr_data_in(fifo_wr_data[port_idx])
            );
        end
    endgenerate

    // ============================================================
    // 입력 큐에 수신 프레임 저장 (각 포트별로 독립 동작)
    // ============================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < NUM_PORTS; i = i + 1) begin
                input_queue[i] <= 0;
                input_queue_valid[i] <= 0;
            end
        end else begin
            for (i = 0; i < NUM_PORTS; i = i + 1) begin
                if (frame_rx_valid[i] && !input_queue_valid[i]) begin
                    // 프레임 수신 시 입력 큐에 저장
                    input_queue[i] <= rx_frame[i];
                    input_queue_valid[i] <= 1;
                end
                // 큐가 처리되면 valid 플래그 해제 (아래 FSM에서 처리)
            end
        end
    end

    // ============================================================
    // MAC Address Learning (수신 시 즉시 학습)
    // ============================================================
    reg src_found;
    reg [ADDR_WIDTH-1:0] src_mac_local [0:NUM_PORTS-1];
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < TABLE_SIZE; i = i + 1) begin
                mac_table_valid[i] <= 0;
                mac_table_addr[i] <= 0;
                mac_table_port[i] <= 0;
            end
            mac_table_next_idx <= 0;
        end else begin
            for (i = 0; i < NUM_PORTS; i = i + 1) begin
                if (frame_rx_valid[i]) begin
                    src_mac_local[i] = rx_frame[i][SRC_ADDR_MSB:SRC_ADDR_LSB];
                    src_found = 0;
                    for (j = 0; j < TABLE_SIZE; j = j + 1) begin
                        if (mac_table_valid[j] && mac_table_addr[j] == src_mac_local[i]) begin
                            src_found = 1;
                            if (mac_table_port[j] != i) begin
                                mac_table_port[j] <= i;
                            end
                        end
                    end
                    if (!src_found) begin
                        mac_table_addr[mac_table_next_idx] <= src_mac_local[i];
                        mac_table_port[mac_table_next_idx] <= i;
                        mac_table_valid[mac_table_next_idx] <= 1;
                        mac_table_next_idx = mac_table_next_idx + 1;
                    end
                end
            end
        end
    end

    // ============================================================
    // Round-Robin 포워딩 FSM
    // ============================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rr_current_port <= 0;
            fwd_state <= S_IDLE;
            current_frame <= 0;
            current_src_port <= 0;
            current_dest_mac <= 0;
            current_src_mac <= 0;
            flood_port_idx <= 0;
            dest_port_reg <= 0;
            dest_found_reg <= 0;
            for (i = 0; i < NUM_PORTS; i = i + 1) begin
                fifo_wr_en[i] <= 0;
                fifo_wr_data[i] <= 0;
            end
        end else begin
            // 기본적으로 FIFO 쓰기 비활성화
            for (i = 0; i < NUM_PORTS; i = i + 1) begin
                fifo_wr_en[i] <= 0;
            end
            
            case (fwd_state)
                S_IDLE: begin
                    // Round-Robin으로 처리할 포트 선택
                    if (input_queue_valid[rr_current_port]) begin
                        // 현재 포트에 처리할 프레임이 있음
                        current_frame <= input_queue[rr_current_port];
                        current_src_port <= rr_current_port;
                        current_dest_mac <= input_queue[rr_current_port][DEST_ADDR_MSB:DEST_ADDR_LSB];
                        current_src_mac <= input_queue[rr_current_port][SRC_ADDR_MSB:SRC_ADDR_LSB];
                        fwd_state <= S_LOOKUP;
                    end else begin
                        // 다음 포트로 이동
                        rr_current_port <= (rr_current_port + 1) % NUM_PORTS;
                    end
                end
                
                S_LOOKUP: begin
                    // MAC 테이블에서 목적지 검색
                    dest_found_reg <= 0;
                    dest_port_reg <= 0;
                    for (j = 0; j < TABLE_SIZE; j = j + 1) begin
                        if (mac_table_valid[j] && mac_table_addr[j] == current_dest_mac) begin
                            dest_port_reg <= mac_table_port[j];
                            dest_found_reg <= 1;
                        end
                    end
                    
                    // 브로드캐스트 또는 목적지 못 찾음 -> Flooding
                    if (current_dest_mac == BROADCAST_ADDR) begin
                        fwd_state <= S_FLOOD;
                        flood_port_idx <= 0;
                    end else begin
                        fwd_state <= S_FORWARD;
                    end
                end
                
                S_FORWARD: begin
                    // Unicast 포워딩
                    if (dest_found_reg) begin
                        if (dest_port_reg != current_src_port) begin
                            fifo_wr_en[dest_port_reg] <= 1;
                            fifo_wr_data[dest_port_reg] <= current_frame;
                        end
                        // Filtering: 목적지가 소스와 같으면 아무것도 안 함
                        // 포워딩 완료, 입력 큐 비우고 다음 포트로
                        input_queue_valid[current_src_port] <= 0;
                        rr_current_port <= (rr_current_port + 1) % NUM_PORTS;
                        fwd_state <= S_IDLE;
                    end else begin
                        // 목적지 못 찾음 -> Flooding으로 전환
                        fwd_state <= S_FLOOD;
                        flood_port_idx <= 0;
                    end
                end
                
                S_FLOOD: begin
                    // Flooding: 소스 포트 제외 모든 포트에 순차적으로 전송
                    if (flood_port_idx != current_src_port) begin
                        fifo_wr_en[flood_port_idx] <= 1;
                        fifo_wr_data[flood_port_idx] <= current_frame;
                    end
                    
                    if (flood_port_idx == NUM_PORTS - 1) begin
                        // Flooding 완료, 입력 큐 비우고 다음 포트로
                        input_queue_valid[current_src_port] <= 0;
                        rr_current_port <= (rr_current_port + 1) % NUM_PORTS;
                        fwd_state <= S_IDLE;
                    end else begin
                        flood_port_idx <= flood_port_idx + 1;
                    end
                end
            endcase
        end
    end
endmodule