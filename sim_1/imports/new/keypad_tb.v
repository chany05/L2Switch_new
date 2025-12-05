`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/10/27 10:00:00
// Design Name: keypad
// Module Name: keypad_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Testbench for the KeyPad module.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module keypad_tb;

    // --- Testbench Parameters ---
    localparam CLK_PERIOD = 10; // 10ns = 100MHz clock

    // --- DUT Inputs ---
    reg clk;
    reg rst;
    reg [2:0] key_col;

    // --- DUT Outputs ---
    wire [3:0] key_row;
    wire [3:0] key_value;

    // --- DUT Instantiation ---
    keypad dut (
        .clk(clk),
        .rst(rst),
        .key_col(key_col),
        .key_row(key_row),
        .key_value(key_value)
    );

    // --- Clock Generation ---
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // --- Test Scenario ---
    initial begin
        $display("--- Testbench Started ---");

        // 1. Reset the system
        rst = 1;
        key_col = 3'b000;
        # (CLK_PERIOD * 5);
        rst = 0;
        $display("Time: %0t ns, System Reset Released.", $time);
        # (CLK_PERIOD * 10);

        // 2. Simulate pressing key '5' (Row 1, Col 1)
        $display("Time: %0t ns, Simulating key press: 5", $time);
        // Wait for DUT to scan Row 1 (4'b0100)
        wait (key_row == 4'b0100);
        key_col = 3'b010; // Assert Col 1
        # (CLK_PERIOD * 2); // Hold the key press for 2 cycles
        key_col = 3'b000; // Release the key
        $display("Time: %0t ns, Key '5' released. Current output: %d", $time, key_value);
        # (CLK_PERIOD * 20);

        // 3. Simulate pressing key '0' (Row 3, Col 1)
        $display("Time: %0t ns, Simulating key press: 0", $time);
        // Wait for DUT to scan Row 3 (4'b0001)
        wait (key_row == 4'b0001);
        key_col = 3'b010; // Assert Col 1
        # (CLK_PERIOD * 2); // Hold the key press
        key_col = 3'b000; // Release the key
        $display("Time: %0t ns, Key '0' released. Current output: %d", $time, key_value);
        # (CLK_PERIOD * 20);

        // 4. Simulate pressing key '*' (10) (Row 3, Col 0)
        $display("Time: %0t ns, Simulating key press: * (10)", $time);
        // Wait for DUT to scan Row 3 (4'b0001)
        wait (key_row == 4'b0001);
        key_col = 3'b100; // Assert Col 0
        # (CLK_PERIOD * 2); // Hold the key press
        key_col = 3'b000; // Release the key
        $display("Time: %0t ns, Key '*' released. Current output: %d", $time, key_value);
        # (CLK_PERIOD * 20);

        // 5. End simulation
        $display("--- Testbench Finished ---");
        $finish;
    end

    // --- Monitor ---
    // Display changes in signals for easier debugging
    initial begin
        $monitor("Time: %0t ns, rst: %b, key_row: %b, key_col: %b, scanned_key: %d, state: %b, key_value: %d",
                 $time, rst, key_row, key_col, dut.scanned_key, dut.state, key_value);
    end

endmodule