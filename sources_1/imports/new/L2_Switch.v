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
        if (rst) begin
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
        .wr_en(fifo_wr_en_in),
        .wr_data(fifo_wr_data_in),
        .full(), // full 신호는 현재 사용하지 않음
        .rd_en(!fifo_empty && !frame_tx_valid_to_unit), // TX 유닛이 유휴 상태일 때만 읽기
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
        .tx_bit(tx_bit_out)
    );

    // FIFO에서 데이터를 읽어 TX Unit으로 전달하는 로직
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_frame_to_unit <= 0;
            frame_tx_valid_to_unit <= 0;
        end else begin
            frame_tx_valid_to_unit <= 0; // 기본적으로 0으로 유지
            if (!fifo_empty && !frame_tx_valid_to_unit) begin
                tx_frame_to_unit <= fifo_rd_data;
                frame_tx_valid_to_unit <= 1;
            end
        end
    end
endmodule

//================================================================
// L2 Switch Main Module
//================================================================
module L2_Switch #(
    parameter NUM_PORTS = 4,
    parameter DEPTH = 16,
    parameter ADDR_WIDTH = 4,
    parameter TABLE_SIZE = 16, // MAC 테이블 크기
    parameter FIFO_DEPTH = 8
)(
    input clk,
    input rst,
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
    reg [$clog2(TABLE_SIZE)-1:0] mac_table_next_idx; // [Refactor] 다음 저장 위치 포인터

    // Main switching logic을 위한 임시 변수 (모듈 레벨에 선언)
    reg [ADDR_WIDTH-1:0] src_mac;
    reg [ADDR_WIDTH-1:0] dest_mac;
    wire dest_found; // [Refactor] 조합 논리로 변경
    reg [$clog2(NUM_PORTS)-1:0] dest_port;
    integer i, j;

    // FIFO interface signals
    wire [DEPTH-1:0] fifo_rd_data [0:NUM_PORTS-1];
    wire fifo_empty [0:NUM_PORTS-1];
    reg fifo_wr_en [0:NUM_PORTS-1];
    reg [DEPTH-1:0] fifo_wr_data [0:NUM_PORTS-1];

    // [Refactor] MAC 테이블 검색을 위한 신호
    reg [ADDR_WIDTH-1:0] lookup_mac;
    wire lookup_found;

    // Generate RX, FIFO, TX units for each port
    genvar port_idx;
    generate
        for (port_idx = 0; port_idx < NUM_PORTS; port_idx = port_idx + 1) begin : port_inst
            // 각 포트를 구성하는 Switch_Port 모듈을 인스턴스화
            Switch_Port #(
                .DEPTH(DEPTH),
                .ADDR_WIDTH(ADDR_WIDTH),
                .FIFO_DEPTH(FIFO_DEPTH)
            ) u_switch_port (
                .clk(clk), .rst(rst),
                .rx_bit_in(rx_bit_in[port_idx]),
                .tx_bit_out(tx_bit_out[port_idx]),
                .rx_frame_out(rx_frame[port_idx]),
                .frame_rx_valid_out(frame_rx_valid[port_idx]),
                .fifo_wr_en_in(fifo_wr_en[port_idx]),
                .fifo_wr_data_in(fifo_wr_data[port_idx])
            );
        end
    endgenerate

    // [Refactor Block 1] MAC Address Learning Logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < TABLE_SIZE; i = i + 1) begin
                mac_table_valid[i] <= 0;
            end
            mac_table_next_idx <= 0;
        end else begin
            // 모든 포트를 순회하며 프레임 수신 시 MAC 주소 학습
            for (i = 0; i < NUM_PORTS; i = i + 1) begin
                if (frame_rx_valid[i]) begin
                    reg src_found;
                    src_mac = rx_frame[i][SRC_ADDR_MSB:SRC_ADDR_LSB];

                    // 1. 테이블에서 Source MAC 검색
                    src_found = 0;
                    for (j = 0; j < TABLE_SIZE; j = j + 1) begin
                        if (mac_table_valid[j] && mac_table_addr[j] == src_mac) begin
                            src_found = 1;
                            // Optional: 장치가 다른 포트로 이동한 경우, 포트 정보 업데이트
                            if (mac_table_port[j] != i) begin
                                mac_table_port[j] <= i;
                            end
                        end
                    end

                    // 2. 테이블에 없으면 새로 추가 (개선된 방식)
                    if (!src_found) begin
                        mac_table_addr[mac_table_next_idx] <= src_mac;
                        mac_table_port[mac_table_next_idx] <= i;
                        mac_table_valid[mac_table_next_idx] <= 1;
                        mac_table_next_idx <= mac_table_next_idx + 1; // 다음 인덱스로 이동
                    end
                end
            end
        end
    end

    // [Refactor Block 2] Frame Forwarding Logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < NUM_PORTS; i = i + 1) begin
                fifo_wr_en[i] <= 0;
                fifo_wr_data[i] <= 0;
            end
        end else begin
            // 기본적으로 모든 FIFO 쓰기 비활성화
            for (i = 0; i < NUM_PORTS; i = i + 1) begin
                fifo_wr_en[i] <= 0;
            end

            // 모든 포트를 순회하며 프레임 포워딩 결정
            for (i = 0; i < NUM_PORTS; i = i + 1) begin
                if (frame_rx_valid[i]) begin
                    reg dest_found_local = 0; // always 블록 내에서 사용할 임시 변수, 0으로 초기화
                    dest_mac = rx_frame[i][DEST_ADDR_MSB:DEST_ADDR_LSB];

                    // 1. 테이블에서 Destination MAC 검색하여 포트 찾기
                    dest_port = 0; // 기본값
                    // dest_found_local = 0; // 선언과 동시에 초기화하므로 이 라인은 제거 가능
                    for (j = 0; j < TABLE_SIZE; j = j + 1) begin
                        if (mac_table_valid[j] && mac_table_addr[j] == dest_mac) begin
                            dest_port = mac_table_port[j];
                            dest_found_local = 1;
                        end
                    end 

                    // 2. 포워딩 규칙 적용
                    if (dest_mac == BROADCAST_ADDR) begin
                        // Case A: Broadcast -> Flooding
                        for (j = 0; j < NUM_PORTS; j = j + 1) begin
                            if (i != j) begin // 수신 포트 제외
                                fifo_wr_en[j] <= 1;
                                fifo_wr_data[j] <= rx_frame[i];
                            end
                        end
                    end else if (dest_found_local) begin
                        // Case B: Unicast (주소 찾음)
                        if (dest_port != i) begin // 목적지가 수신 포트와 다르면 -> Forwarding
                            fifo_wr_en[dest_port] <= 1;
                            fifo_wr_data[dest_port] <= rx_frame[i];
                        end
                        // 목적지가 수신 포트와 같으면 -> Filtering (아무것도 안 함)
                    end else begin
                        // Case C: Unicast (주소 못 찾음) -> Flooding
                        for (j = 0; j < NUM_PORTS; j = j + 1) begin
                            if (i != j) begin // 수신 포트 제외
                                fifo_wr_en[j] <= 1;
                                fifo_wr_data[j] <= rx_frame[i]; // 원본 프레임을 그대로 전달
                            end
                        end
                    end
                end
            end
        end
    end
endmodule