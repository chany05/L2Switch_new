`timescale 1ps / 1ps
////////////////////////
module keypad(
    input clk, // 시스템 클럭
    input rst,
    input [2:0] key_col,
    output reg [3:0] key_row,
    output reg [3:0] key_value
);

    reg [1:0] key_counter;

    // FSM 상태 정의
    localparam IDLE = 1'b0;
    localparam PRESSED = 1'b1;

    reg state;
    reg [3:0] scanned_key; // 현재 스캔된 키 값


    // Row scanning counter
    always @(posedge clk or posedge rst) begin
        if (rst)
            key_counter <= 2'b00;
        else
            key_counter <= key_counter + 1;
    end

    // Row driver logic (one-hot active high)
    always @(posedge clk or posedge rst) begin
        if (rst)
            key_row <= 4'b0000;
        else begin
            case (key_counter)
                2'b00: key_row <= 4'b1000; // Activate Row 0
                2'b01: key_row <= 4'b0100; // Activate Row 1
                2'b10: key_row <= 4'b0010; // Activate Row 2
                2'b11: key_row <= 4'b0001; // Activate Row 3
            endcase
        end
    end

    // Key value decoding logic (내부 스캔 값 업데이트)
    // 조합논리로 변경: key_row 또는 key_col이 변경될 때마다 즉시 scanned_key가 업데이트됨
    always @(*) begin
        // rst 신호는 FSM에서 처리하므로 여기서는 생략 가능
        case (key_row)
            4'b1000: // Row 0 is active
                case (key_col)
                    3'b100: scanned_key = 4'd1;
                    3'b010: scanned_key = 4'd2;
                    3'b001: scanned_key = 4'd3;
                    default: scanned_key = 4'hF;
                endcase
            4'b0100: // Row 1 is active
                case (key_col)
                    3'b100: scanned_key = 4'd4;
                    3'b010: scanned_key = 4'd5;
                    3'b001: scanned_key = 4'd6;
                    default: scanned_key = 4'hF;
                endcase
            4'b0010: // Row 2 is active
                case (key_col)
                    3'b100: scanned_key = 4'd7;
                    3'b010: scanned_key = 4'd8;
                    3'b001: scanned_key = 4'd9;
                    default: scanned_key = 4'hF;
                endcase
            4'b0001: // Row 3 is active
                case (key_col)
                    3'b100: scanned_key = 4'd0; // '*' key
                    3'b010: scanned_key = 4'd0;
                    3'b001: scanned_key = 4'd0; // '#' key
                    default: scanned_key = 4'hF;
                endcase
            default: scanned_key = 4'hF;
        endcase
    end

    // FSM for storing the last pressed key (디바운싱을 간단히 처리하기 위해)
    always @(*) begin
        if (rst) begin
            state <= IDLE;
            key_value <= 4'hF; // 초기 출력값
        end else begin
            case (state)
                IDLE: begin
                    if (scanned_key != 4'hF) begin
                        key_value <= scanned_key; // 새로운 키가 눌리면 출력값 업데이트
                        state <= PRESSED;
                    end
                end
                PRESSED: begin
                    if (scanned_key == 4'hF) begin
                        state <= IDLE; // 키가 떼어지면 다시 IDLE 상태로
                    end
                end
            endcase
        end
    end

endmodule