`timescale 1ps / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/26 14:00:00
// Module Name: tb_L2_Switch
// Description: Testbench for L2_Switch module
//////////////////////////////////////////////////////////////////////////////////


//================================================================
// TestNode: EndDevice를 래핑하여 테스트를 용이하게 하는 헬퍼 모듈
//================================================================
module TestNode #(
    parameter DEPTH = 16,
    parameter ADDR_WIDTH = 4,
    parameter MAC_ADDRESS = 4'd0
)(
    input clk,
    input rst,
    input rx_bit,
    output tx_bit
);
    // 내부 신호
    reg [DEPTH-1:0] frame_to_send;
    reg send_trigger;
    wire [DEPTH-1:0] received_frame;
    wire frame_received_valid;

    // EndDevice 인스턴스화
    EndDevice #(
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .MAC_ADDRESS(MAC_ADDRESS)
    ) dut (
        .clk(clk), .rst(rst),
        .tx_frame(frame_to_send),
        .frame_tx_valid(send_trigger),
        .tx_bit(tx_bit),
        .rx_bit(rx_bit),
        .rx_frame(received_frame),
        .frame_rx_valid(frame_received_valid),
        .rx_data_out()
    );

    // 프레임 전송을 위한 태스크
    task send_frame(input [DEPTH-1:0] frame);
        begin
            frame_to_send = frame;
            send_trigger = 1;
            @(posedge clk);
            send_trigger = 0;
            $display("[%0t] Node %h: Sent frame %h", $time, MAC_ADDRESS, frame);
        end
    endtask

    // 프레임 수신 모니터링
    always @(posedge frame_received_valid) begin
        $display("[%0t] Node %h: Received frame %h", $time, MAC_ADDRESS, received_frame);
    end

endmodule


//================================================================
// L2_Switch Testbench
//================================================================
module tb_L2_Switch;

    // Parameters
    parameter NUM_PORTS = 4;
    parameter DEPTH = 16;
    parameter ADDR_WIDTH = 4;
    parameter TABLE_SIZE = 16;
    parameter FIFO_DEPTH = 8;
    parameter CLK_PERIOD = 10;

    // Frame Structure
    localparam SFD = 4'b0101; // 프레임 시작을 알리는 하강 에지를 위해 첫 비트가 0이어야 함
    localparam BROADCAST_ADDR = {ADDR_WIDTH{1'b1}};

    // MAC Addresses for TestNodes
    localparam MAC_A = 4'hA;
    localparam MAC_B = 4'hB;
    localparam MAC_C = 4'hC;
    localparam MAC_D = 4'hD;

    // Testbench signals
    reg clk;
    reg rst;
    wire [NUM_PORTS-1:0] rx_bit_from_nodes;
    wire [NUM_PORTS-1:0] tx_bit_to_nodes;

    // Instantiate the L2_Switch (DUT)
    L2_Switch #(
        .NUM_PORTS(NUM_PORTS),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .TABLE_SIZE(TABLE_SIZE),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rx_bit_in(rx_bit_from_nodes),
        .tx_bit_out(tx_bit_to_nodes)
    );

    // Instantiate TestNodes for each port
    TestNode #(.MAC_ADDRESS(MAC_A)) node_A (.clk(clk), .rst(rst), .rx_bit(tx_bit_to_nodes[0]), .tx_bit(rx_bit_from_nodes[0]));
    TestNode #(.MAC_ADDRESS(MAC_B)) node_B (.clk(clk), .rst(rst), .rx_bit(tx_bit_to_nodes[1]), .tx_bit(rx_bit_from_nodes[1]));
    TestNode #(.MAC_ADDRESS(MAC_C)) node_C (.clk(clk), .rst(rst), .rx_bit(tx_bit_to_nodes[2]), .tx_bit(rx_bit_from_nodes[2]));
    TestNode #(.MAC_ADDRESS(MAC_D)) node_D (.clk(clk), .rst(rst), .rx_bit(tx_bit_to_nodes[3]), .tx_bit(rx_bit_from_nodes[3]));

    // Clock generation
    always # (CLK_PERIOD / 2) clk = ~clk;

    // Test sequence
    initial begin
        $display("========================================");
        $display("Starting L2 Switch Test");
        $display("========================================");

        // 1. Initial Reset
        clk = 0;
        rst = 1;
        repeat (2) @(posedge clk);
        rst = 0;
        $display("\n[%0t] System reset released.", $time);
        repeat (5) @(posedge clk);

        // --- Test Scenario 1: MAC Learning and Flooding ---
        $display("\n[SCENARIO 1] Node A sends to Node B. Expect flooding to B, C, D.");
        // Frame: A -> B
        // Switch learns MAC_A is on port 0.
        // Since MAC_B is unknown, switch floods to ports 1, 2, 3.
        node_A.send_frame({SFD, MAC_B, MAC_A, 4'h1});
        
        // Wait for transmission and forwarding to complete
        repeat (50) @(posedge clk);

        // --- Test Scenario 2: Unicast Forwarding ---
        $display("\n[SCENARIO 2] Node B responds to Node A. Expect unicast to A.");
        // Frame: B -> A
        // Switch learns MAC_B is on port 1.
        // Since MAC_A is known (on port 0), switch forwards only to port 0.
        node_B.send_frame({SFD, MAC_A, MAC_B, 4'h2});

        // Wait for transmission and forwarding to complete
        repeat (50) @(posedge clk);

        // --- Test Scenario 3: Broadcast ---
        $display("\n[SCENARIO 3] Node C sends a broadcast frame. Expect flooding to A, B, D.");
        // Frame: C -> Broadcast
        // Switch learns MAC_C is on port 2.
        // Frame is broadcast, so switch floods to all other ports (0, 1, 3).
        node_C.send_frame({SFD, BROADCAST_ADDR, MAC_C, 4'h3});

        repeat (50) @(posedge clk);

        $display("\nTest Finished.");
        $finish;
    end

endmodule


/* --- Simulation Log Expectation ---

[SCENARIO 1] Node A sends to Node B. Expect flooding to B, C, D.
[time] Node A: Sent frame {SFD, B, A, 1111}
[time] Node B: Received frame {SFD, B, A, 1111}
[time] Node C: Received frame {SFD, B, A, 1111}
[time] Node D: Received frame {SFD, B, A, 1111}

[SCENARIO 2] Node B responds to Node A. Expect unicast to A.
[time] Node B: Sent frame {SFD, A, B, 2222}
[time] Node A: Received frame {SFD, A, B, 2222}
 (Node C and D should NOT receive this frame)

[SCENARIO 3] Node C sends a broadcast frame. Expect flooding to A, B, D.
[time] Node C: Sent frame {SFD, F, C, 3333}
[time] Node A: Received frame {SFD, F, C, 3333}
[time] Node B: Received frame {SFD, F, C, 3333}
[time] Node D: Received frame {SFD, F, C, 3333}

*/