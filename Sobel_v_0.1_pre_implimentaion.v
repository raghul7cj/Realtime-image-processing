//the below code doesnt work at 1920 x 1080 p due to timing constraints involved in convolution 
//future plans can be using ddr4 ram and ps block and/or lower resolution to 480p
`timescale 1ns / 1ps

// Top-level Sobel filter AXI-Stream module for 1920x1080p@60fps
// Pipelined and BRAM-based with 3 line buffers

module sobel_axi_stream (
    input wire clk,
    input wire rst,

    // AXI4-Stream Slave (Input video stream)
    input wire [23:0] s_axis_tdata,
    input wire        s_axis_tvalid,
    input wire        s_axis_tlast,
    input wire        s_axis_tuser,
    output wire       s_axis_tready,

    // AXI4-Stream Master (Output processed video stream)
    output reg [23:0] m_axis_tdata,
    output reg        m_axis_tvalid,
    output reg        m_axis_tlast,
    output reg        m_axis_tuser,
    input wire        m_axis_tready
);

    parameter IMAGE_WIDTH = 1920;
    parameter PIXEL_DEPTH = 8; // per channel

    wire [7:0] gray_pixel;
    wire gray_valid;

    // Convert RGB to Grayscale
    rgb2gray u_rgb2gray (
        .clk(clk),
        .rst(rst),
        .rgb(s_axis_tdata),
        .rgb_valid(s_axis_tvalid),
        .gray(gray_pixel),
        .gray_valid(gray_valid)
    );

    // Line Buffer Module (3 lines)
    wire [8*9-1:0] window_flat;
    wire       window_valid;

    line_buffer_3line #(
        .IMAGE_WIDTH(IMAGE_WIDTH)
    ) u_line_buffer (
        .clk(clk),
        .rst(rst),
        .pixel_in(gray_pixel),
        .pixel_valid(gray_valid),
        .window_flat(window_flat),
        .window_valid(window_valid)
    );

    // Sobel Filter Processing
    wire [7:0] sobel_pixel;
    wire       sobel_valid;

    sobel_core u_sobel_core (
        .clk(clk),
        .rst(rst),
        .window_flat(window_flat),
        .window_valid(window_valid),
        .pixel_out(sobel_pixel),
        .valid_out(sobel_valid)
    );

    // Output pixel formatting (grayscale to RGB)
    always @(posedge clk) begin
        if (rst) begin
            m_axis_tvalid <= 0;
            m_axis_tdata  <= 0;
            m_axis_tlast  <= 0;
            m_axis_tuser  <= 0;
        end else begin
            m_axis_tvalid <= sobel_valid;
            m_axis_tdata  <= {sobel_pixel, sobel_pixel, sobel_pixel};
            m_axis_tlast  <= s_axis_tlast;
            m_axis_tuser  <= s_axis_tuser;
        end
    end

    assign s_axis_tready = m_axis_tready;

endmodule

// ========== RGB to Grayscale Module ==========
module rgb2gray (
    input  wire        clk,
    input  wire        rst,
    input  wire [23:0] rgb,
    input  wire        rgb_valid,
    output reg  [7:0]  gray,
    output reg         gray_valid
);
    always @(posedge clk) begin
        if (rst) begin
            gray <= 0;
            gray_valid <= 0;
        end else begin
            if (rgb_valid) begin
                gray <= (rgb[23:16] >> 2) + (rgb[15:8] >> 1) + (rgb[7:0] >> 2); // Approx Y = 0.25R + 0.5G + 0.25B
                gray_valid <= 1;
            end else begin
                gray_valid <= 0;
            end
        end
    end
endmodule

// ========== Line Buffer with 3 Lines using BRAM ==========
module line_buffer_3line #(
    parameter IMAGE_WIDTH = 1920
)(
    input wire clk,
    input wire rst,
    input wire [7:0] pixel_in,
    input wire       pixel_valid,
    output reg [8*9-1:0] window_flat,
    output reg       window_valid
);

    (* ram_style = "block" *) reg [7:0] line0[0:IMAGE_WIDTH-1];
    (* ram_style = "block" *) reg [7:0] line1[0:IMAGE_WIDTH-1];
    (* ram_style = "block" *) reg [7:0] line2[0:IMAGE_WIDTH-1];

    integer col = 0;

    always @(posedge clk) begin
        if (rst) begin
            col <= 0;
            window_valid <= 0;
        end else if (pixel_valid) begin
            // Shift lines
            line0[col] <= line1[col];
            line1[col] <= line2[col];
            line2[col] <= pixel_in;

            if (col >= 2) begin
                window_flat[8*0 +: 8] <= line0[col-2];
                window_flat[8*1 +: 8] <= line0[col-1];
                window_flat[8*2 +: 8] <= line0[col];
                window_flat[8*3 +: 8] <= line1[col-2];
                window_flat[8*4 +: 8] <= line1[col-1];
                window_flat[8*5 +: 8] <= line1[col];
                window_flat[8*6 +: 8] <= line2[col-2];
                window_flat[8*7 +: 8] <= line2[col-1];
                window_flat[8*8 +: 8] <= line2[col];
                window_valid <= 1;
            end else begin
                window_valid <= 0;
            end

            col <= (col + 1) % IMAGE_WIDTH;
        end else begin
            window_valid <= 0;
        end
    end
endmodule

// ========== Sobel Core Filter ==========
module sobel_core (
    input wire clk,
    input wire rst,
    input wire [71:0] window_flat,
    input wire       window_valid,
    output reg [7:0] pixel_out,
    output reg       valid_out
);
    wire [7:0] w0 = window_flat[8*0 +: 8];
    wire [7:0] w1 = window_flat[8*1 +: 8];
    wire [7:0] w2 = window_flat[8*2 +: 8];
    wire [7:0] w3 = window_flat[8*3 +: 8];
    wire [7:0] w4 = window_flat[8*4 +: 8];
    wire [7:0] w5 = window_flat[8*5 +: 8];
    wire [7:0] w6 = window_flat[8*6 +: 8];
    wire [7:0] w7 = window_flat[8*7 +: 8];
    wire [7:0] w8 = window_flat[8*8 +: 8];

    integer Gx, Gy;
    integer sum;

    always @(posedge clk) begin
        if (rst) begin
            pixel_out <= 0;
            valid_out <= 0;
        end else if (window_valid) begin
            Gx = -w0 + w2
               - 2*w3 + 2*w5
               - w6 + w8;

            Gy = -w0 - 2*w1 - w2
               + w6 + 2*w7 + w8;

            sum = (Gx*Gx + Gy*Gy) >> 8; // Approximation of sqrt
            if (sum > 255) sum = 255;
            if (sum < 0) sum = 0;

            pixel_out <= sum[7:0];
            valid_out <= 1;
        end else begin
            valid_out <= 0;
        end
    end
endmodule
