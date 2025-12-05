`timescale 1ps / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/26 17:30:00
// Module Name: tb_FPGA_Simulator_Top
// Description: FPGA_Simulator_Top 모듈의 테스트벤치
//////////////////////////////////////////////////////////////////////////////////

module tb_FPGA_Simulator_Top;

    // DUT 입력
    reg FPGA_CLK;
    reg FPGA_RST_BTN;
    reg [7:0] FPGA_SWITCHES;
    reg FPGA_SEND_BTN;
    reg [2:0] KEYPAD_COL;

    // DUT 출력
    wire [3:0] KEYPAD_ROW;
    wire [7:0] FPGA_LEDS;
    wire lcd_enb;
    wire lcd_rs, lcd_rw;
    wire [7:0] lcd_data;

    // DUT 인스턴스화
    FPGA_Simulator_Top dut (
        .FPGA_CLK(FPGA_CLK),
        .FPGA_RST_BTN(FPGA_RST_BTN),
        .FPGA_SWITCHES(FPGA_SWITCHES),
        .FPGA_SEND_BTN(FPGA_SEND_BTN),
        .KEYPAD_COL(KEYPAD_COL),
        .KEYPAD_ROW(KEYPAD_ROW),
        .FPGA_LEDS(FPGA_LEDS),
        .lcd_enb(lcd_enb),
        .lcd_rs(lcd_rs),
        .lcd_rw(lcd_rw),
        .lcd_data(lcd_data)
    );

    // 클럭 생성 (50MHz, 20ns 주기)
    initial begin
        FPGA_CLK = 0;
        forever #1 FPGA_CLK = ~FPGA_CLK;
    end

    // 테스트 시나리오
    initial begin
        $display("==================================================");
        $display("Testbench for FPGA_Simulator_Top Started");
        $display("==================================================");

        // 1. 초기화 및 리셋
        FPGA_RST_BTN = 1'b0; // Active-Low 리셋 버튼 누름
        FPGA_SWITCHES = 8'h00;
        FPGA_SEND_BTN = 1'b0;
        KEYPAD_COL = 3'b000; // 키패드 입력 없음
        
        #10; // 리셋 안정화 시간
        FPGA_RST_BTN = 1'b1; // 리셋 버튼 해제
        #10;
        $display("[%0t] System Reset Released.", $time);

        // 2. 페이로드 설정 (키패드 '5' 입력 시뮬레이션)
        // Keypad.v 분석: '5'는 Row 1, Col 1에 해당.
        // dut가 KEYPAD_ROW를 4'b0100 (Row 1 활성화)으로 만들 때,
        // KEYPAD_COL을 3'b010 (Col 1 활성화)으로 설정하여 키 입력을 시뮬레이션.
        $display("[%0t] Waiting to simulate keypad press for payload '5'...", $time);
        wait (dut.KEYPAD_ROW == 4'b0100); // Row 1이 스캔될 때까지 대기
        #1; // 안정성을 위해 약간의 지연
        KEYPAD_COL = 3'b010; // '5' 키에 해당하는 열을 활성화
        #15; // 키가 눌린 상태를 몇 클럭 동안 유지
        KEYPAD_COL = 3'b000; // 키를 뗌 (모든 열 비활성화)
        $display("[%0t] Keypad '5' pressed. Payload should be updated.", $time);
        #10; // 페이로드 값이 업데이트될 시간을 줌

        // 페이로드 값 확인 (LED 하위 4비트)
        if (FPGA_LEDS[3:0] == 4'h5) $display("[SUCCESS] Payload is correctly set to 5. (LEDS[3:0]=%h)", FPGA_LEDS[3:0]);
        else $display("[FAILURE] Payload is NOT set correctly. (LEDS[3:0]=%h)", FPGA_LEDS[3:0]);

        // 3. 프레임 전송 (Node A -> Node C)
        // DIP 스위치 설정: DST=C(1100), SRC=A(1010)
        FPGA_SWITCHES = 8'hCA;
        #10;
        $display("[%0t] Set Switches: DST=C, SRC=A (FPGA_SWITCHES = 8'h%h)", $time, FPGA_SWITCHES);

        // 전송 버튼 누르기 (1 클럭 사이클 동안)
        FPGA_SEND_BTN = 1'b1;
        #20; // 1 클럭 (20ns) 동안 버튼 누름
        FPGA_SEND_BTN = 1'b0;
        $display("[%0t] Send button pressed. Frame transmission from A to C initiated.", $time);

        // 4. 시뮬레이션 진행 및 종료
        #50; // 스위치를 통해 프레임이 전달되고 LED가 업데이트될 충분한 시간

        // 최종 결과 확인: Payload는 5, 수신 노드는 C (LED[6]=1)
        // FPGA_LEDS 예상 값: 8'b0100_0101 = 8'h45
        if (FPGA_LEDS == 8'h45)
            $display("[SUCCESS] Final LED value is correct: %h. Frame successfully received by Node C.", FPGA_LEDS);
        else
            $display("[FAILURE] Final LED value is incorrect: %h. Expected 8'h45.", FPGA_LEDS);

        $display("[%0t] Simulation finished.", $time);
        $finish;
    end

    // 모니터링


endmodule