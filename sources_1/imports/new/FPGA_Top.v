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
    input  FPGA_CLK,               // FPGA 보드의 클럭 (예: 50MHz 또는 100MHz)
    input  FPGA_RST_BTN,           // 리셋 버튼 (Active-Low 가정)
    input  FPGA_ADD_PACKET_BTN,    // 페이로드 추가 버튼

    // 2. 사용자 입력 (프레임 생성용)
    input  [7:0] FPGA_SWITCHES,    // DIP 스위치 ([7:4]=DST, [3:0]=SRC)
    input  FPGA_SEND_BTN,          // 프레임 전송 버튼
    input  [2:0] KEYPAD_COL,       // 키패드 열 입력
    output [3:0] KEYPAD_ROW,       // 키패드 행 출력

    // 3. 상태 표시 출력
    output reg [7:0] FPGA_LEDS,    // LED (하위 4비트: payload, 상위 4비트: 수신 표시)

    // 4. Text LCD 출력
    output lcd_enb,
    output lcd_rs, lcd_rw,
    output [7:0] lcd_data
);

    // 시스템 리셋 (Active-Low 버튼)
    wire sys_rst = ~FPGA_RST_BTN;

    // ---------------------------------------------------------------------
    // 파라미터 및 상수 정의
    // ---------------------------------------------------------------------
    localparam NUM_PORTS = 4;
    localparam SFD       = 4'b0101;   // Start Frame Delimiter
    localparam MAC_A = 4'hA;
    localparam MAC_B = 4'hB;
    localparam MAC_C = 4'hC;
    localparam MAC_D = 4'hD;

    // ---------------------------------------------------------------------
    // 사용자 입력 해석
    // ---------------------------------------------------------------------
    wire [3:0] dest_addr_from_sw = FPGA_SWITCHES[7:4]; // 목적지 주소
    wire [3:0] src_node_select   = FPGA_SWITCHES[3:0]; // 출발 노드 선택

    // ---------------------------------------------------------------------
    // 페이로드 (키패드 입력) 관리
    // ---------------------------------------------------------------------
    reg [3:0] payload; // 현재 페이로드 값
    wire [3:0] keypad_value_wire;

    // 키패드 인스턴스
    keypad keypad_inst (
        .clk(FPGA_CLK),
        .rst(sys_rst),
        .key_col(KEYPAD_COL),
        .key_row(KEYPAD_ROW),
        .key_value(keypad_value_wire)
    );

    // 유효한 키 입력이 있으면 payload 업데이트 (F키는 무시)
    always @(posedge FPGA_CLK or posedge sys_rst) begin
        if (sys_rst) begin
            payload <= 4'b0;
        end else if (keypad_value_wire != 4'hF) begin
            payload <= keypad_value_wire;
        end
    end

    // ---------------------------------------------------------------------
    // 패킷 큐 (최대 4개) 정의
    // ---------------------------------------------------------------------
    reg [15:0] pending_frames [0:3];   // 저장된 프레임
    reg [1:0]  pending_src   [0:3];   // 프레임 출발 노드 인덱스 (0~3)
    reg        pending_valid [0:3];   // 유효 플래그
    integer i;

    // 버튼 디바운싱 (1클럭 펄스 생성)
    reg send_btn_d1;
    reg add_pkt_btn_d1;
    wire send_trigger    = FPGA_SEND_BTN    && !send_btn_d1;
    wire add_packet_trigger = FPGA_ADD_PACKET_BTN && !add_pkt_btn_d1;

    always @(posedge FPGA_CLK or posedge sys_rst) begin
        if (sys_rst) begin
            send_btn_d1    <= 0;
            add_pkt_btn_d1 <= 0;
            for (i = 0; i < 4; i = i + 1) begin
                pending_valid[i] <= 0;
            end
        end else begin
            send_btn_d1    <= FPGA_SEND_BTN;
            add_pkt_btn_d1 <= FPGA_ADD_PACKET_BTN;
        end
    end

    // ---------------------------------------------------------------------
    // 프레임 큐에 패킷 추가 로직 (add_packet_trigger)
    // ---------------------------------------------------------------------
    reg flag;
    reg [1:0] src_idx;
    always @(posedge FPGA_CLK or posedge sys_rst) begin
        if (sys_rst) begin
            // already cleared in reset above
            flag <= 0;
        end else if (add_packet_trigger) begin
            // 현재 선택된 src 노드 인덱스 매핑
            flag = 1;
            case (src_node_select)
                MAC_A: src_idx = 2'd0;
                MAC_B: src_idx = 2'd1;
                MAC_C: src_idx = 2'd2;
                MAC_D: src_idx = 2'd3;
                default: src_idx = 2'd0;
            endcase
            // 빈 슬롯 찾기
            for (i = 0; i < 4; i = i + 1) begin
                if ((!pending_valid[i]) && flag) begin
                    pending_frames[i] <= {SFD, dest_addr_from_sw, src_node_select, payload};
                    pending_src[i]   <= src_idx;
                    pending_valid[i] <= 1'b1;
                    flag = 0; // break loop
                end
            end
            flag = 0;
        end
    end

    // --- 내부 통신 신호 ---
    reg [15:0] frame_to_send [0:NUM_PORTS-1];
    reg        frame_tx_valid [0:NUM_PORTS-1];

    // --- 전송 제어 로직 ---
    // 전송 버튼이 눌리면, DIP 스위치로 선택된 노드에 전송 신호를 보냄
    always @(posedge FPGA_CLK or posedge sys_rst) begin
        if (sys_rst) begin
            for (i = 0; i < NUM_PORTS; i = i + 1) begin
                frame_tx_valid[i] <= 0;
                frame_to_send[i]  <= 0;
            end
        end else begin
            // 기본적으로 1클럭 뒤에 자동 0 (non‑blocking)
            for (i = 0; i < NUM_PORTS; i = i + 1) begin
                frame_tx_valid[i] <= 0;
            end
            if (send_trigger) begin
                for (i = 0; i < 4; i = i + 1) begin
                    if (pending_valid[i]) begin
                        case (pending_src[i])
                            2'd0: begin frame_to_send[0] <= pending_frames[i]; frame_tx_valid[0] <= 1'b1; end
                            2'd1: begin frame_to_send[1] <= pending_frames[i]; frame_tx_valid[1] <= 1'b1; end
                            2'd2: begin frame_to_send[2] <= pending_frames[i]; frame_tx_valid[2] <= 1'b1; end
                            2'd3: begin frame_to_send[3] <= pending_frames[i]; frame_tx_valid[3] <= 1'b1; end
                        endcase
                        pending_valid[i] <= 0; // 전송 후 슬롯 비우기
                    end
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // 내부 통신 신호 정의
    // ---------------------------------------------------------------------
    wire [NUM_PORTS-1:0] rx_bit_from_nodes;
    wire [NUM_PORTS-1:0] tx_bit_to_nodes;
    wire [15:0] received_frame [0:NUM_PORTS-1];
    wire [NUM_PORTS-1:0] frame_rx_valid;

    // ---------------------------------------------------------------------
    // L2 스위치 인스턴스화
    // ---------------------------------------------------------------------
    L2_Switch dut_switch (
        .clk(FPGA_CLK),
        .rst(sys_rst),
        .rx_bit_in(rx_bit_from_nodes),
        .tx_bit_out(tx_bit_to_nodes)
    );

    // ---------------------------------------------------------------------
    // EndDevice 인스턴스화 (4개)
    // ---------------------------------------------------------------------
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

    // ---------------------------------------------------------------------
    // LED 표시 로직 (수신 LED 초기화 및 페이로드 표시)
    // ---------------------------------------------------------------------
    reg [NUM_PORTS-1:0] frame_rx_valid_d1;
    wire [NUM_PORTS-1:0] frame_rx_trigger;

    always @(posedge FPGA_CLK or posedge sys_rst) begin
        if (sys_rst) begin
            frame_rx_valid_d1 <= 0;
        end else begin
            frame_rx_valid_d1 <= frame_rx_valid;
        end
    end
    assign frame_rx_trigger = frame_rx_valid & ~frame_rx_valid_d1; // 상승 엣지 감지

    always @(posedge FPGA_CLK or posedge sys_rst) begin
        if (sys_rst) begin
            FPGA_LEDS <= 8'b0;
        end else begin
            // 하위 4비트: 현재 payload 표시
            FPGA_LEDS[3:0] <= payload;
            // 전송 시 LED 초기화
            if (send_trigger) begin
                FPGA_LEDS[7:4] <= 4'b0000;
            end else begin
                if (frame_rx_trigger[0]) FPGA_LEDS[4] <= 1'b1;
                if (frame_rx_trigger[1]) FPGA_LEDS[5] <= 1'b1;
                if (frame_rx_trigger[2]) FPGA_LEDS[6] <= 1'b1;
                if (frame_rx_trigger[3]) FPGA_LEDS[7] <= 1'b1;
            end
        end
    end

    // ---------------------------------------------------------------------
    // Text LCD 인스턴스화
    // ---------------------------------------------------------------------
    text_lcd lcd_inst (
        .clk(FPGA_CLK),
        .rst(sys_rst),
        .payload_in(FPGA_LEDS),
        .addr_in({dest_addr_from_sw, src_node_select}),
        .lcd_enb(lcd_enb),
        .lcd_rs(lcd_rs),
        .lcd_rw(lcd_rw),
        .lcd_data(lcd_data)
    );

endmodule