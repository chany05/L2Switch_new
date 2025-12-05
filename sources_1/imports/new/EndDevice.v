`timescale 1ps / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/24 11:36:41
// Module Name: EndDevice
// Description: 프레임 병렬 입력 후 시프트 아웃 단말기
//////////////////////////////////////////////////////////////////////////////////

module shift_register #(
    parameter DEPTH = 16
)(
    input clk,
    input rst,
    input shift_in,
    input load,
    input [DEPTH-1:0] parallel_in,
    output shift_out,
    output reg [DEPTH-1:0] data_out
); 
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            data_out <= 0;
        end else if(load) begin
            data_out <= parallel_in;
        end else begin
            data_out <= {data_out[DEPTH-2:0], shift_in};
        end
    end
    assign shift_out = data_out[DEPTH-1];
endmodule

//================================================================
// TX Unit: 병렬 데이터를 직렬로 전송하는 모듈
//================================================================
module TX_Unit #(
    parameter DEPTH = 16
)(
    input clk,
    input rst,
    input [DEPTH-1:0] tx_frame, // 프레임 입력
    input frame_tx_valid,       // 프레임 전송 유효 신호
    output tx_bit,              // 시프트 아웃 비트
    output tx_busy              // 전송 중 표시
);
    wire tx_shift_out_bit;
    reg tx_load_en;  // 프레임 로드 신호
    reg tx_shift_en; // 시프트 동작 제어 신호
    reg [$clog2(DEPTH):0] tx_shift_cnt; // 카운터 크기 1 증가

    localparam TX_IDLE = 1'b0;
    localparam TX_SHIFT = 1'b1;
    reg tx_state;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            tx_state <= TX_IDLE;
            tx_load_en <= 0;
            tx_shift_en <= 0;
            tx_shift_cnt <= 0;
        end else begin
            tx_load_en <= 0;

            case(tx_state)
                TX_IDLE: begin
                    if(frame_tx_valid) begin
                        tx_state <= TX_SHIFT;
                        tx_load_en <= 1; // 한 클럭 동안만 로드 신호 활성화
                        tx_shift_en <= 1; // 시프트 시작
                        tx_shift_cnt <= DEPTH; // 카운터를 DEPTH로 초기화
                    end
                end
                TX_SHIFT: begin
                    if(tx_shift_cnt > 0) begin // 카운터가 0이 될 때까지 시프트 (DEPTH full cycles)
                        tx_shift_cnt <= tx_shift_cnt - 1;
                    end else begin
                        tx_state <= TX_IDLE;
                        tx_shift_en <= 0;
                    end
                end
            endcase
        end
    end

    shift_register #(
        .DEPTH(DEPTH)
    ) u_tx_shift_register (
        .clk(clk),
        .rst(rst),
        .shift_in(1'b0), // 시프트 인은 0으로 고정
        .load(frame_tx_valid),
        .parallel_in(tx_frame),
        .shift_out(tx_shift_out_bit)
    );

    assign tx_bit = tx_shift_en ? tx_shift_out_bit : 1'b1;
    assign tx_busy = (tx_state == TX_SHIFT);  // 전송 중이면 busy
endmodule

//================================================================
// RX Unit: 직렬 데이터를 병렬로 수신하는 모듈
//================================================================
module RX_Unit #(
    parameter DEPTH = 16,
    parameter ADDR_WIDTH = 4, // 주소 폭을 4비트로 변경
    parameter MAC_ADDRESS = 4'd0  // 고유 MAC 주소
)(
    input clk,
    input rst,
    input rx_bit,                       // 직렬 데이터 입력
    output reg [DEPTH-1:0] rx_frame,    // 수신된 병렬 프레임
    output reg frame_rx_valid,          // 수신 프레임 유효 신호
    output [DEPTH-1:0] rx_data_out      // RX 시프트 레지스터 실시간 출력 (디버깅용)
);
    // 프레임 구조 정의 (SFD 4bit, DST 4bit, SRC 4bit, PAYLOAD 4bit)
    localparam SFD_WIDTH = 4;
    localparam DEST_ADDR_MSB = DEPTH - SFD_WIDTH - 1; // 목적지 주소 MSB 위치
    localparam DEST_ADDR_LSB = DEPTH - SFD_WIDTH - ADDR_WIDTH;  // 목적지 주소 LSB 위치
    localparam BROADCAST_ADDR = {ADDR_WIDTH{1'b1}};

    // always 블록 밖에서 wire 선언
    wire [ADDR_WIDTH-1:0] dest_addr;

    wire [DEPTH-1:0] rx_shift_reg_out;
    reg rx_shift_en; // RX 시프트 레지스터 활성화 신호
    reg [$clog2(DEPTH)-1:0] rx_shift_cnt;
    reg rx_bit_d1; // 하강 에지 감지를 위해 이전 rx_bit 값을 저장

    localparam RX_IDLE = 2'b00;
    localparam RX_SHIFT = 2'b01;
    localparam RX_DONE = 2'b10;
    reg [1:0] rx_state;

    assign dest_addr = rx_shift_reg_out[DEST_ADDR_MSB:DEST_ADDR_LSB];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state <= RX_IDLE;
            rx_shift_en <= 0;
            rx_shift_cnt <= 0;
            rx_frame <= 0;
            frame_rx_valid <= 0;
            rx_bit_d1 <= 1'b1; // 유휴 상태인 High로 초기화
        end else begin
            frame_rx_valid <= 0;
            rx_bit_d1 <= rx_bit; // 매 클럭 rx_bit 상태 업데이트

            case (rx_state)
                RX_IDLE: begin
                    // 시작 비트(High -> Low 하강 에지) 감지
                    if (rx_bit_d1 == 1'b1 && rx_bit == 1'b0) begin
                        rx_state <= RX_SHIFT;
                        rx_shift_en <= 1;
                        rx_shift_cnt <= DEPTH - 1;
                    end
                end
                RX_SHIFT: begin
                    if (rx_shift_cnt > 0) begin
                        rx_shift_cnt <= rx_shift_cnt - 1;
                    end else begin
                        rx_state <= RX_DONE;
                        rx_shift_en <= 0; // 시프트 완료
                        if (MAC_ADDRESS == BROADCAST_ADDR || dest_addr == MAC_ADDRESS || dest_addr == BROADCAST_ADDR) begin // assign으로 연결된 wire 사용
                            rx_frame <= rx_shift_reg_out; // 내 주소 또는 브로드캐스트 주소일 경우에만 데이터 저장
                            frame_rx_valid <= 1;          // 수신 완료 신호 1클럭 동안 활성화
                        end
                    end
                end
                RX_DONE: begin
                    // 안정화 1클럭
                    rx_state <= RX_IDLE; // IDLE 상태로 복귀하여 다음 프레임 대기
                end
            endcase
        end
    end

    shift_register #(
        .DEPTH(DEPTH)
    ) u_rx_shift_register (
        .clk(clk),
        .rst(rst),
        .shift_in(rx_bit), // 직렬 데이터를 시프트 레지스터로 입력
        .load(1'b0),       // RX에서는 병렬 로드 사용 안함
        .parallel_in(0),   // Don't care
        .shift_out(),      // 사용 안함
        .data_out(rx_shift_reg_out)
    );

    assign rx_data_out = rx_shift_reg_out;
endmodule

//================================================================
// EndDevice: TX Unit과 RX Unit을 포함하는 최상위 모듈
//================================================================
module EndDevice #(
    parameter DEPTH = 16,
    parameter ADDR_WIDTH = 4, // 주소 폭을 4비트로 변경
    parameter MAC_ADDRESS = 4'd0  // 고유 MAC 주소
)(
    input clk,
    input rst,
    // TX Ports
    input [DEPTH-1:0] tx_frame,
    input frame_tx_valid,
    output tx_bit,
    // RX Ports
    input rx_bit,
    output [DEPTH-1:0] rx_frame,
    output frame_rx_valid,
    output [DEPTH-1:0] rx_data_out
);

    // TX Unit 인스턴스화
    TX_Unit #( .DEPTH(DEPTH) ) u_tx_unit (
        .clk(clk), .rst(rst),
        .tx_frame(tx_frame), .frame_tx_valid(frame_tx_valid),
        .tx_bit(tx_bit)
    );

    // RX Unit 인스턴스화
    RX_Unit #(
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .MAC_ADDRESS(MAC_ADDRESS)
    ) u_rx_unit (
        .clk(clk), .rst(rst),
        .rx_bit(rx_bit),
        .rx_frame(rx_frame), .frame_rx_valid(frame_rx_valid), .rx_data_out(rx_data_out)
    );
endmodule
