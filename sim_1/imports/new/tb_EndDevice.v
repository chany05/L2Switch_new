`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/24 22:00:00
// Module Name: tb_EndDevice
// Description: Testbench for EndDevice module with loopback test
//////////////////////////////////////////////////////////////////////////////////

module tb_EndDevice;

    // Parameters
    parameter DEPTH = 16;
    parameter CLK_PERIOD = 10; // 10ns = 100MHz clock
    parameter ADDR_WIDTH = 4;

    // DUT Address
    parameter DUT_ADDR = 4'd1;
    // Testbench Address (Source Address)
    parameter TB_ADDR = 4'd2;

    // Testbench signals
    reg clk;
    reg rst;
    
    // DUT Inputs
    reg [DEPTH-1:0] tb_tx_frame;
    reg tb_frame_tx_valid;
    
    // DUT Outputs
    wire [DEPTH-1:0] tb_rx_frame;
    wire tb_frame_rx_valid;
    wire [DEPTH-1:0] tb_rx_data_out;
    
    // Loopback wire
    wire serial_line;

    // The serial line is high when idle (pulled up)
    // This handles the 'z' state from tx_bit
    pullup(serial_line);

    // Instantiate the Device Under Test (DUT)
    EndDevice #(
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .MAC_ADDRESS(DUT_ADDR)
    ) dut (
        .clk(clk),
        .rst(rst),
        // TX
        .tx_frame(tb_tx_frame),
        .frame_tx_valid(tb_frame_tx_valid),
        .tx_bit(serial_line), // TX output drives the serial line
        // RX
        .rx_bit(serial_line), // RX input is connected to the same serial line
        .rx_frame(tb_rx_frame),
        .frame_rx_valid(tb_frame_rx_valid),
        .rx_data_out(tb_rx_data_out)
    );

    // Clock generation
    always begin
        clk = 1'b0;
        #(CLK_PERIOD / 2);
        clk = 1'b1;
        #(CLK_PERIOD / 2);
    end

    // Test sequence
    initial begin
        $display("========================================");
        $display("Starting EndDevice Loopback Test");
        $display("========================================");

        // 1. Initial Reset
        tb_tx_frame = 0;
        tb_frame_tx_valid = 0;
        rst = 1;
        repeat(2) @(posedge clk);
        rst = 0;
        repeat(5) @(posedge clk);

        // 2. Test Case 1: Transmit to DUT's specific address (DUT_ADDR)
        // Frame Format: {SFD[15:12], Dest[11:8], Src[7:4], Payload[3:0]}
        tb_tx_frame = {4'b0101, DUT_ADDR, TB_ADDR, 4'hA}; // SFD=0101, Dest=1, Src=2, Payload=A
        $display("\n[Test 1] Transmitting frame to DUT address (0x%h). Expect SUCCESS.", DUT_ADDR);
        $display("         Frame: 0x%h", tb_tx_frame);
        tb_frame_tx_valid = 1;
        @(posedge clk);
        tb_frame_tx_valid = 0;

        // Wait for reception to complete
        wait (tb_frame_rx_valid);
        @(posedge clk); // Wait one more cycle for the data to be stable in tb_rx_frame

        // 3. Verification 1
        if (tb_rx_frame === {4'b0101, DUT_ADDR, TB_ADDR, 4'hA}) begin
            $display("[SUCCESS] Received data 0x%h matches transmitted data.", tb_rx_frame);
        end else begin
            $error("[FAILURE] Mismatch! Transmitted: 0x%h, Received: 0x%h", {4'b0101, DUT_ADDR, TB_ADDR, 4'hA}, tb_rx_frame);
        end

        repeat(10) @(posedge clk); // Idle time

        // 4. Test Case 2: Transmit to a different address. DUT should ignore this.
        tb_tx_frame = {4'b0101, 4'd5, TB_ADDR, 4'hB}; // Dest = 5
        $display("\n[Test 2] Transmitting frame to wrong address (0x%h). Expect IGNORE.", 4'd5);
        $display("         Frame: 0x%h", tb_tx_frame);
        tb_frame_tx_valid = 1;
        @(posedge clk);
        tb_frame_tx_valid = 0;

        // Wait for a while to see if it gets received (it shouldn't)
        repeat(DEPTH + 5) @(posedge clk);
        if (tb_frame_rx_valid == 1'b0) begin
            $display("[SUCCESS] DUT correctly ignored the frame for the wrong address.");
        end else begin
            $error("[FAILURE] DUT received a frame it should have ignored! Received: 0x%h", tb_rx_frame);
        end

        repeat(10) @(posedge clk); // Idle time

        // 5. Test Case 3: Transmit to broadcast address
        tb_tx_frame = {4'b0101, {ADDR_WIDTH{1'b1}}, TB_ADDR, 4'hC}; // Dest = 4'b1111 (Broadcast)
        $display("\n[Test 3] Transmitting frame to broadcast address (0x%h). Expect SUCCESS.", {ADDR_WIDTH{1'b1}});
        $display("         Frame: 0x%h", tb_tx_frame);
        tb_frame_tx_valid = 1;
        @(posedge clk);
        tb_frame_tx_valid = 0;

        // Wait for reception
        wait (tb_frame_rx_valid);
        @(posedge clk);

        // Verification 3
        if (tb_rx_frame === {4'b0101, {ADDR_WIDTH{1'b1}}, TB_ADDR, 4'hC}) begin
            $display("[SUCCESS] Received broadcast data 0x%h matches transmitted data.", tb_rx_frame);
        end else begin
            $error("[FAILURE] Mismatch! Transmitted: 0x%h, Received: 0x%h", {4'b0101, {ADDR_WIDTH{1'b1}}, TB_ADDR, 4'hC}, tb_rx_frame);
        end

        $display("\nTest Finished.");
        $finish;
    end

endmodule