`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/27 14:00:00
// Module Name: tb_text_lcd
// Description: text_lcd 모듈의 기능 검증을 위한 테스트벤치
//////////////////////////////////////////////////////////////////////////////////

module tb_text_lcd;

    // Testbench 내부 신호 선언
    reg clk;
    reg rst;
    reg [7:0] payload_in;
    reg [7:0] addr_in;

    // DUT(Device Under Test) 출력 신호
    wire lcd_enb;
    wire lcd_rs, lcd_rw;
    wire [7:0] lcd_data;

    // text_lcd 모듈 인스턴스화
    text_lcd dut (
        .clk(clk),
        .rst(rst),
        .payload_in(payload_in),
        .addr_in(addr_in),
        .lcd_enb(lcd_enb),
        .lcd_rs(lcd_rs),
        .lcd_rw(lcd_rw),
        .lcd_data(lcd_data)
    );

    // 1. 클럭 생성 (50MHz, 20ns 주기)
    initial begin
        clk = 0;
        forever #10 clk = ~clk; // 10ns 마다 토글 -> 20ns 주기
    end

    // 2. 테스트 시나리오
    initial begin
        $display("========================================");
        $display("Testbench for text_lcd Started");
        $display("========================================");

        // 초기화
        rst = 1'b1; // Active-High 리셋
        payload_in = 8'h00;
        addr_in = 8'h00;
        #100; // 100ns 동안 리셋 유지

        rst = 1'b0; // 리셋 해제
        $display("[%0t ns] System Reset Released.", $time);
        #100;

        // 테스트할 입력 값 설정
        // SRC = A (1010), DST = C (1100) -> addr_in[7:0] = {DST, SRC} = 8'b1100_1010 = 8'hCA
        // Payload = 5 -> payload_in[3:0] = 4'b0101 = 4'h5
        addr_in = 8'hCA;
        payload_in = 8'h05; // payload_in의 하위 4비트만 사용됨
        $display("[%0t ns] Set addr_in = %h, payload_in = %h", $time, addr_in, payload_in);

        // LCD가 여러 번 화면을 갱신할 수 있도록 충분한 시간 동안 시뮬레이션 실행
        #50000;

        $display("[%0t ns] Simulation Finished.", $time);
        $finish;
    end

    // 3. 모니터링
    initial begin
        // 주요 신호들의 변화를 시뮬레이션 콘솔에 출력
        $monitor("[%0t ns] rst=%b, state=%d, counter=%d | rs=%b, rw=%b, data=0x%h",
                 $time, rst, dut.state, dut.counter, lcd_rs, lcd_rw, lcd_data);
    end

endmodule