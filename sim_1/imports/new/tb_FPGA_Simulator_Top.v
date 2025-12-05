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
    reg FPGA_ADD_PACKET_BTN;
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
        .FPGA_ADD_PACKET_BTN(FPGA_ADD_PACKET_BTN),
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
    integer i;
    // 테스트 시나리오
    initial begin
        $display("==================================================");
        $display("Testbench for FPGA_Simulator_Top Started");
        $display("==================================================");

        // 1. 초기화 및 리셋
        FPGA_RST_BTN = 1'b0; // Active-Low 리셋 버튼 누름
        FPGA_SWITCHES = 8'h00;
        FPGA_SEND_BTN = 1'b0;
        FPGA_ADD_PACKET_BTN = 1'b0;
        KEYPAD_COL = 3'b000; // 키패드 입력 없음
        
        #10; // 리셋 안정화 시간
        FPGA_RST_BTN = 1'b1; // 리셋 버튼 해제
        #10;
        $display("[%0t] System Reset Released.", $time);

        // 2. 페이로드 설정 (키패드 '5' 입력 시뮬레이션)
        $display("[%0t] Waiting to simulate keypad press for payload '5'...", $time);
        wait (dut.KEYPAD_ROW == 4'b0100); // Row 1이 스캔될 때까지 대기
        #1;
        KEYPAD_COL = 3'b010; // '5' 키에 해당하는 열을 활성화
        #15;
        KEYPAD_COL = 3'b000; // 키를 뗌
        $display("[%0t] Keypad '5' pressed. Payload should be updated.", $time);
        #10;

        // 페이로드 값 확인 (LED 하위 4비트)
        if (FPGA_LEDS[3:0] == 4'h5)
            $display("[SUCCESS] Payload is correctly set to 5. (LEDS[3:0]=%h)", FPGA_LEDS[3:0]);
        else
            $display("[FAILURE] Payload is NOT set correctly. (LEDS[3:0]=%h)", FPGA_LEDS[3:0]);

        // 3. 패킷 추가 (여러 패킷을 큐에 쌓음)
        // 첫 번째 패킷: DST=C, SRC=A, payload=5
        FPGA_SWITCHES = 8'hCA; // DST=C(1100), SRC=A(1010)
        #20;
        FPGA_ADD_PACKET_BTN = 1'b1;
        #20;
        FPGA_ADD_PACKET_BTN = 1'b0;
        #30; // 안정화 대기
        $display("[%0t] Packet 1 added: DST=C, SRC=A, Payload=5", $time);

        // 두 번째 패킷: DST=D, SRC=B, payload=5
        FPGA_SWITCHES = 8'hDB; // DST=D(1101), SRC=B(1011)
        #20;
        FPGA_ADD_PACKET_BTN = 1'b1;
        #20;
        FPGA_ADD_PACKET_BTN = 1'b0;
        #30; // 안정화 대기
        $display("[%0t] Packet 2 added: DST=D, SRC=B, Payload=5", $time);

        // 세 번째 패킷: DST=A, SRC=C, payload=5
        FPGA_SWITCHES = 8'hAC; // DST=A(1010), SRC=C(1100)
        #20;
        FPGA_ADD_PACKET_BTN = 1'b1;
        #20;
        FPGA_ADD_PACKET_BTN = 1'b0;
        #30; // 안정화 대기
        $display("[%0t] Packet 3 added: DST=A, SRC=C, Payload=5", $time);

        $display("[%0t] All packets queued. Ready to send.", $time);

        // 전송 버튼 누르기
        FPGA_SEND_BTN = 1'b1;
        #20;
        FPGA_SEND_BTN = 1'b0;
        $display("[%0t] Send button pressed. All queued frames transmitted.", $time);

        // 4. 시뮬레이션 진행 및 종료
        #500; // 스위치를 통해 프레임이 전달되고 LED가 업데이트될 충분한 시간

        // 최종 결과 확인
        // 수신 노드: A(LED[4]), C(LED[6]), D(LED[7]) => LED[7:4] = 4'b1101 = 0xD
        // payload = 5 => LED[3:0] = 0x5
        $display("[%0t] Final FPGA_LEDS = %h", $time, FPGA_LEDS);
        if (FPGA_LEDS[7:4] == 4'b1101)
            $display("[SUCCESS] Receive LEDs correct: LED[7:4]=%b (A,C,D received)", FPGA_LEDS[7:4]);
        else
            $display("[FAILURE] Receive LEDs incorrect: LED[7:4]=%b, Expected 1101", FPGA_LEDS[7:4]);

        // 첫 번째 패킷: DST=C, SRC=D, payload=5
        FPGA_SWITCHES = 8'hCD; // DST=C(1100), SRC=D(1011)
        #20;
        FPGA_ADD_PACKET_BTN = 1'b1;
        #20;
        FPGA_ADD_PACKET_BTN = 1'b0;
        #30; // 안정화 대기
        $display("[%0t] Packet 1 added: DST=C, SRC=D, Payload=5", $time);

        // 두 번째 패킷: DST=D, SRC=B, payload=5
        FPGA_SWITCHES = 8'hDB; // DST=D(1101), SRC=B(1011)
        #20;
        FPGA_ADD_PACKET_BTN = 1'b1;
        #20;
        FPGA_ADD_PACKET_BTN = 1'b0;
        #30; // 안정화 대기
        $display("[%0t] Packet 2 added: DST=D, SRC=B, Payload=5", $time);

        $display("[%0t] All packets queued. Ready to send.", $time);

        // 전송 버튼 누르기
        FPGA_SEND_BTN = 1'b1;
        #20;
        FPGA_SEND_BTN = 1'b0;
        $display("[%0t] Send button pressed. All queued frames transmitted.", $time);

        // 4. 시뮬레이션 진행 및 종료
        #500; // 스위치를 통해 프레임이 전달되고 LED가 업데이트될 충분한 시간

        // 최종 결과 확인
        // 수신 노드: A(LED[4]), C(LED[6]), D(LED[7]) => LED[7:4] = 4'b1101 = 0xD
        // payload = 5 => LED[3:0] = 0x5
        $display("[%0t] Final FPGA_LEDS = %h", $time, FPGA_LEDS);
        if (FPGA_LEDS[7:4] == 4'b1100)
            $display("[SUCCESS] Receive LEDs correct: LED[7:4]=%b (C,D received)", FPGA_LEDS[7:4]);
        else
            $display("[FAILURE] Receive LEDs incorrect: LED[7:4]=%b, Expected 1100", FPGA_LEDS[7:4]);

        $display("[%0t] Simulation finished.", $time);
        $finish;
    end

endmodule