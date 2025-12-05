`timescale 1ps / 1ps
////////////////////////////////////////
module text_lcd(
    input clk, rst,
    input [7:0] payload_in,
    input [7:0] addr_in,
    output lcd_enb,
    output reg lcd_rs, lcd_rw,
    output reg [8-1:0] lcd_data
);

// 3-bit 상태 레지스터
reg [3-1:0] state;

// 상태 파라미터 정의
parameter delay           = 3'b000,
          function_set    = 3'b001,
          entry_mode      = 3'b010,
          display_onoff   = 3'b011,
          line1           = 3'b100,
          line2           = 3'b101,
          delay_t         = 3'b110,
          clear_display   = 3'b111;
    // 주소 값에 따른 ASCII 문자 코드
    // 주소 및 페이로드 값에 따른 ASCII 코드 정의
localparam ASCII_A = 8'h41, ASCII_B = 8'h42, ASCII_C = 8'h43, ASCII_D = 8'h44;
localparam ASCII_0 = 8'h30, ASCII_1 = 8'h31, ASCII_2 = 8'h32, ASCII_3 = 8'h33,
            ASCII_4 = 8'h34, ASCII_5 = 8'h35, ASCII_6 = 8'h36, ASCII_7 = 8'h37,
            ASCII_8 = 8'h38, ASCII_9 = 8'h39;
wire [3:0] dest_addr = addr_in[7:4];
wire [3:0] src_addr  = addr_in[3:0]; // Top 모듈에서 payload가 연결됨
wire [3:0] payload   = payload_in[3:0];
// 카운터 정의
integer counter;

// 카운터 로직 (각 상태별 지연 시간 카운트)
always @ (posedge clk or posedge rst)
begin
    if (rst)
        counter = 0;
    else
        case (state)
            delay:
                begin
                    if (counter == 70)
                        counter = 0;
                    else
                        counter = counter + 1;
                end
            function_set:
                begin
                    if (counter == 30)
                        counter = 0;
                    else
                        counter = counter + 1;
                end
            display_onoff:
                begin
                    if (counter == 30)
                        counter = 0;
                    else
                        counter = counter + 1;
                end
            entry_mode:
                begin
                    if (counter == 30)
                        counter = 0;
                    else
                        counter = counter + 1;
                end
            line1:
                begin
                    if (counter == 20)
                        counter = 0;
                    else
                        counter = counter + 1;
                end
            line2:
                begin
                    if (counter == 20)
                        counter = 0;
                    else
                        counter = counter + 1;
                end
            delay_t:
                begin
                    if (counter == 400)
                        counter = 0;
                    else
                        counter = counter + 1;
                end
            clear_display:
                begin
                    if (counter == 200)
                        counter = 0;
                    else
                        counter = counter + 1;
                end
        endcase
end

// 상태 천이 로직 (State Transition Logic)
always @ (posedge clk or posedge rst) begin
    if (rst)
        state = delay;
    else
        case (state)
            delay:          if (counter == 70) state = function_set;
            function_set:   if (counter == 30) state = display_onoff;
            display_onoff:  if (counter == 30) state = entry_mode;
            entry_mode:     if (counter == 30) state = line1;
            line1:          if (counter == 20) state = line2;
            line2:          if (counter == 20) state = delay_t;
            delay_t:        if (counter == 400) state = clear_display;
            clear_display:  if (counter == 200) state = line1;
        endcase
end

// LCD 제어 신호 및 데이터 출력 로직
always @ (posedge clk or posedge rst) begin
    if (rst) begin
        lcd_rs = 1'b1;
        lcd_rw = 1'b1;
        lcd_data = 8'b0000_0000;
    end
    else begin
        case (state)
            function_set: begin
                lcd_rs = 1'b0; // 명령어 레지스터 선택 (IR)
                lcd_rw = 1'b0; // 쓰기 동작 (Write)
                // DL=1 (8-bit), N=1 (2-line), F=0 (5x8 dots) -> 0011 1100
                lcd_data = 8'b0011_1100;
            end
            display_onoff: begin
                lcd_rs = 1'b0; // IR
                lcd_rw = 1'b0; // Write
                // D=1 (Display ON), C=0 (Cursor OFF), B=0 (Blink OFF) -> 0000 1100
                lcd_data = 8'b0000_1100;
            end
            entry_mode: begin
                lcd_rs = 1'b0; // IR
                lcd_rw = 1'b0; // Write
                // I/D=1 (Increment), S=0 (Shift OFF) -> 0000 0110
                lcd_data = 8'b0000_0110;
            end
            line1: begin 
                lcd_rs <= 1'b1; // 데이터 전송 (RS=1)
                case (counter) // 12개의 문자/공백을 출력
                    0: begin lcd_rs <= 1'b0; lcd_data <= 8'b1000_0000; end // 1번째 라인 시작 주소 (0x00)
                    1: lcd_data <= 8'h73; // s
                    2: lcd_data <= 8'h72; // r                        
                    3: lcd_data <= 8'h63; // c
                    4: lcd_data <= 8'h3A; // :
                    5: case(src_addr) // src 주소 표시
                                4'hA: lcd_data <= ASCII_A;
                                4'hB: lcd_data <= ASCII_B;
                                4'hC: lcd_data <= ASCII_C;
                                4'hD: lcd_data <= ASCII_D;
                                default: lcd_data <= 8'h3F; // '?'
                           endcase
                    6: lcd_data <= 8'h20; // [공백]
                    7: lcd_data <= 8'h64; // d
                    8: lcd_data <= 8'h73; // s
                    9: lcd_data <= 8'h74; // t                        
                    10: lcd_data <= 8'h3A; // :
                    11: case(dest_addr) // dst 주소 표시
                                 4'hA: lcd_data <= ASCII_A;
                                 4'hB: lcd_data <= ASCII_B;
                                 4'hC: lcd_data <= ASCII_C;
                                 4'hD: lcd_data <= ASCII_D;
                                 default: lcd_data <= 8'h3F; // '?'
                        endcase
                    default: lcd_rs <= 1'b0; 
                endcase
            end
                
            // ===================================================
            // Line 2: 'PAYLOAD:' 출력
            // ===================================================
            line2: begin 
                lcd_rs <= 1'b1; // 데이터 전송 (RS=1)
                case (counter)
                    0: begin lcd_rs <= 1'b0; lcd_data <= 8'b1100_0000; end // 2번째 라인 시작 주소 (0x40)
                    1: lcd_data <= 8'h50; // P
                    2: lcd_data <= 8'h41; // A
                    3: lcd_data <= 8'h59; // Y
                    4: lcd_data <= 8'h4C; // L                        
                    5: lcd_data <= 8'h4F; // O
                    6: lcd_data <= 8'h41; // A
                    7: lcd_data <= 8'h44; // D
                    8: lcd_data <= 8'h3A; // :
                    9: case(payload) // 페이로드 값 표시
                                4'h0: lcd_data <= ASCII_0; 4'h1: lcd_data <= ASCII_1;
                                4'h2: lcd_data <= ASCII_2; 4'h3: lcd_data <= ASCII_3;
                                4'h4: lcd_data <= ASCII_4; 4'h5: lcd_data <= ASCII_5;
                                4'h6: lcd_data <= ASCII_6; 4'h7: lcd_data <= ASCII_7;
                                4'h8: lcd_data <= ASCII_8; 4'h9: lcd_data <= ASCII_9;
                                default: lcd_data <= 8'h3F; // '?'
                        endcase
                    // 페이로드는 한 자리이므로 나머지 공간은 공백 처리
                    10: lcd_data <= 8'h20; // [공백]
                    11: lcd_data <= 8'h20; // [공백]
                    default: lcd_rs <= 1'b0; 
                endcase
             end
            delay_t: begin
                lcd_rs = 1'b0; // IR
                lcd_rw = 1'b0; // Write
                // Return Home (Cursor/Display Home) -> 0000 0010
                lcd_data = 8'b0000_0010;
            end
            clear_display: begin
                lcd_rs = 1'b0; // IR
                lcd_rw = 1'b0; // Write
                // Clear Display -> 0000 0001
                lcd_data = 8'b0000_0001;
            end
            default: begin
                lcd_rs = 1'b1; // 기본값으로 둔 안전 상태
                lcd_rw = 1'b1;
                lcd_data = 8'b0000_0000;
            end
        endcase
    end
end

assign lcd_enb = clk;

endmodule