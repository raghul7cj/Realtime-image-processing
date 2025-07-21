`timescale 1ns / 1ps
module inversion #(
    parameter DATA_WIDTH = 24
)(
    // Clock & reset (active-low)
    input  wire                   aclk,
    input  wire                   aresetn,

    // Slave AXI4-Stream Interface
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,
    input  wire                   s_axis_tuser,

    // Master AXI4-Stream Interface
    output reg  [DATA_WIDTH-1:0]  m_axis_tdata,
    output reg                    m_axis_tvalid,
    input  wire                   m_axis_tready,
    output reg                    m_axis_tlast,
    output reg                    m_axis_tuser
);

    // We drive ready whenever the downstream is ready
    assign s_axis_tready = m_axis_tready;

    // Invert each 8-bit color channel: ~x == 255 - x
    // Propagate tlast and tuser so video-out sees proper sync
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_tvalid <= 1'b0;
            m_axis_tdata  <= {DATA_WIDTH{1'b0}};
            m_axis_tlast  <= 1'b0;
            m_axis_tuser  <= 1'b0;
        end else begin
            if (s_axis_tvalid && s_axis_tready) begin
                // Byte-wise inversion
                m_axis_tdata <= {
                    ~s_axis_tdata[23:16],
                    ~s_axis_tdata[15: 8],
                    ~s_axis_tdata[ 7: 0]
                };
                m_axis_tlast  <= s_axis_tlast;
                m_axis_tuser  <= s_axis_tuser;
                m_axis_tvalid <= 1'b1;
            end
            // Once the data has been accepted downstream, clear valid
            else if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
            end
        end
    end

endmodule
