`timescale 1ps / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/26 17:00:00
// Module Name: FPGA_Simulator_Top
// Description: FPGA 내부에 L2 스위치와 여러 단말을 구성한 통신 시뮬레이터.
//              - DIP 스위치로 출발/목적지 주소 설정
//              - 버튼으로 페이로드 설정 및 전송 트리거
//////////////////////////////////////////////////////////////////////////////////
module FPGA_Simulator_Top (
    // 1. 시스템 입력
    input FPGA_CLK,         // FPGA 보드의 클럭 (예: 50MHz 또는 100MHz)
    input FPGA_RST_BTN,     // 리셋 버튼 (Active-Low 가정)

    // 2. 사용자 입력 (프레임 생성용)
    input [7:0] FPGA_SWITCHES,  // 8개 DIP 스위치 ([7:4]:DST, [3:0]:SRC 선택)
    input FPGA_SEND_BTN,    // 프레임 전송을 위한 푸시 버튼
    input [2:0] KEYPAD_COL,     // 키패드 열 입력
    output [3:0] KEYPAD_ROW,    // 키패드 행 출력

    // 3. 상태 표시 출력
    output reg [7:0] FPGA_LEDS, // LED로 상태 및 페이로드 값 표시

    // 4. Text LCD 출력
    output lcd_enb,
    output lcd_rs, lcd_rw,
    output [7:0] lcd_data
);

    // 시스템 리셋 신호 생성 (버튼은 Active-Low이므로 반전)
    wire sys_rst = ~FPGA_RST_BTN;

    // --- 파라미터 및 상수 정의 ---
    localparam NUM_PORTS = 4;
    localparam SFD = 4'b0101;
    localparam MAC_A = 4'hA;
    localparam MAC_B = 4'hB;
    localparam MAC_C = 4'hC;
    localparam MAC_D = 4'hD;

    // --- 사용자 입력 해석 ---
    wire [3:0] dest_addr_from_sw = FPGA_SWITCHES[7:4]; // DIP 스위치 상위 4개 = 목적지 주소
    wire [3:0] src_node_select   = FPGA_SWITCHES[3:0]; // DIP 스위치 하위 4개 = 출발지 노드 선택
    reg  [3:0] payload;                                // 페이로드 값 (키패드 입력 대용)

    // --- 버튼 입력 처리 (1클럭 펄스 생성, Debouncing은 생략) ---
    reg send_btn_d1;
    wire send_trigger = FPGA_SEND_BTN && !send_btn_d1;

    always @(posedge FPGA_CLK or posedge sys_rst) begin
        if (sys_rst) begin
            send_btn_d1 <= 0;
        end else begin
            send_btn_d1 <= FPGA_SEND_BTN;
        end
    end
    
    // --- 키패드 모듈 연결 ---
    wire [3:0] keypad_value_wire; // KeyPad 모듈의 출력을 받을 와이어

    keypad keypad_inst (
        .clk(FPGA_CLK),
        .rst(sys_rst),
        .key_col(KEYPAD_COL),       // 키패드 열 입력을 모듈에 연결
        .key_row(KEYPAD_ROW),       // 모듈의 행 출력을 외부 핀으로 연결
        .key_value(keypad_value_wire) // 모듈의 키 값 출력을 와이어에 연결
    );

    // 페이로드 설정 로직 (키패드 값으로 업데이트)
    always @(posedge FPGA_CLK or posedge sys_rst) begin
        if (sys_rst) begin
            payload <= 4'b0;
        end else if (keypad_value_wire != 4'hF) begin // 유효한 키 입력이 있을 때만
            payload <= keypad_value_wire; // payload 값을 키패드 값으로 업데이트
        end
    end

    // --- 내부 통신 신호 ---
    wire [NUM_PORTS-1:0] rx_bit_from_nodes;
    wire [NUM_PORTS-1:0] tx_bit_to_nodes;
    
    reg [15:0] frame_to_send [0:NUM_PORTS-1];
    reg frame_tx_valid [0:NUM_PORTS-1];

    wire [15:0] received_frame [0:NUM_PORTS-1]; // Unpacked array 유지
    wire [NUM_PORTS-1:0] frame_rx_valid;       // Packed array로 변경

    // --- 전송 제어 로직 ---
    // 전송 버튼이 눌리면, DIP 스위치로 선택된 노드에 전송 신호를 보냄
    always @(posedge FPGA_CLK or posedge sys_rst) begin
        if (sys_rst) begin
            frame_tx_valid[0] <= 0; frame_tx_valid[1] <= 0;
            frame_tx_valid[2] <= 0; frame_tx_valid[3] <= 0;
        end else begin
            // 1클럭 후에 자동으로 0이 되도록 non-blocking 할당
            frame_tx_valid[0] <= 0; frame_tx_valid[1] <= 0;
            frame_tx_valid[2] <= 0; frame_tx_valid[3] <= 0;

            if (send_trigger) begin
                // 출발지 노드에 따라 해당 프레임과 valid 신호 설정
                case (src_node_select)
                    MAC_A: begin frame_to_send[0] <= {SFD, dest_addr_from_sw, MAC_A, payload}; frame_tx_valid[0] <= 1; end
                    MAC_B: begin frame_to_send[1] <= {SFD, dest_addr_from_sw, MAC_B, payload}; frame_tx_valid[1] <= 1; end
                    MAC_C: begin frame_to_send[2] <= {SFD, dest_addr_from_sw, MAC_C, payload}; frame_tx_valid[2] <= 1; end
                    MAC_D: begin frame_to_send[3] <= {SFD, dest_addr_from_sw, MAC_D, payload}; frame_tx_valid[3] <= 1; end
                    default: ; // 의도치 않은 Latch 생성을 방지
                endcase
            end
        end
    end

    // --- L2 스위치 인스턴스화 ---
    L2_Switch dut_switch (
        .clk(FPGA_CLK),
        .rst(sys_rst),
        .rx_bit_in(rx_bit_from_nodes),
        .tx_bit_out(tx_bit_to_nodes)
    );

    // --- 4개의 단말(EndDevice) 인스턴스화 ---
    EndDevice #(.MAC_ADDRESS(MAC_A)) node_A (
        .clk(FPGA_CLK), .rst(sys_rst),
        .tx_frame(frame_to_send[0]), .frame_tx_valid(frame_tx_valid[0]), .tx_bit(rx_bit_from_nodes[0]),
        .rx_bit(tx_bit_to_nodes[0]), .rx_frame(received_frame[0]), .frame_rx_valid(frame_rx_valid[0])
    );
    EndDevice #(.MAC_ADDRESS(MAC_B)) node_B (
        .clk(FPGA_CLK), .rst(sys_rst),
        .tx_frame(frame_to_send[1]), .frame_tx_valid(frame_tx_valid[1]), .tx_bit(rx_bit_from_nodes[1]),
        .rx_bit(tx_bit_to_nodes[1]), .rx_frame(received_frame[1]), .frame_rx_valid(frame_rx_valid[1])
    );
    EndDevice #(.MAC_ADDRESS(MAC_C)) node_C (
        .clk(FPGA_CLK), .rst(sys_rst),
        .tx_frame(frame_to_send[2]), .frame_tx_valid(frame_tx_valid[2]), .tx_bit(rx_bit_from_nodes[2]),
        .rx_bit(tx_bit_to_nodes[2]), .rx_frame(received_frame[2]), .frame_rx_valid(frame_rx_valid[2])
    );
    EndDevice #(.MAC_ADDRESS(MAC_D)) node_D (
        .clk(FPGA_CLK), .rst(sys_rst),
        .tx_frame(frame_to_send[3]), .frame_tx_valid(frame_tx_valid[3]), .tx_bit(rx_bit_from_nodes[3]),
        .rx_bit(tx_bit_to_nodes[3]), .rx_frame(received_frame[3]), .frame_rx_valid(frame_rx_valid[3])
    );

    // --- LED 제어를 위한 1클럭 펄스 생성 ---
    reg [NUM_PORTS-1:0] frame_rx_valid_d1;
    wire [NUM_PORTS-1:0] frame_rx_trigger;

    always @(posedge FPGA_CLK or posedge sys_rst) begin
        if (sys_rst) frame_rx_valid_d1 <= 0;
        else         frame_rx_valid_d1 <= frame_rx_valid;
    end

    assign frame_rx_trigger = frame_rx_valid & ~frame_rx_valid_d1; // 상승 엣지 검출

    // --- 상태 표시 로직 (LED) --- 
    always @(posedge FPGA_CLK or posedge sys_rst) begin
        if (sys_rst) begin
            FPGA_LEDS <= 8'b0;
        end else begin
            // 하위 4개 LED는 현재 페이로드 값 표시
            FPGA_LEDS[3:0] <= payload; // payload는 지속적으로 표시

            // 새로운 프레임 전송 시 수신 LED 초기화
            if (send_trigger) begin
                FPGA_LEDS[7:4] <= 4'b0000;
            end else begin
                // 각 노드의 프레임 수신 시 해당 LED를 1로 설정
                if (frame_rx_trigger[0]) FPGA_LEDS[4] <= 1'b1;
                if (frame_rx_trigger[1]) FPGA_LEDS[5] <= 1'b1;
                if (frame_rx_trigger[2]) FPGA_LEDS[6] <= 1'b1;
                if (frame_rx_trigger[3]) FPGA_LEDS[7] <= 1'b1;
            end
        end
    end

    // --- Text LCD 모듈 인스턴스화 ---
    text_lcd lcd_inst (
        .clk(FPGA_CLK),
        .rst(sys_rst),
        .payload_in(FPGA_LEDS), // payload 값을 payload_in에 직접 연결
        .addr_in({dest_addr_from_sw, src_node_select}), // {dst, src} 주소 전달
        .lcd_enb(lcd_enb),
        .lcd_rs(lcd_rs),
        .lcd_rw(lcd_rw),
        .lcd_data(lcd_data)
    );

endmodule