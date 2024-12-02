`include "../../../defines/defines.svh"

// module DirectionSelectorModel #(
//     parameter DEPTH = 8,
//     parameter ADDR_WIDTH = $clog2(DEPTH)
// ) (
//     input logic [DEPTH-1:0] ready,
//     input logic [DEPTH-1:0][ADDR_WIDTH-1:0] index,
//     input logic [DEPTH-1:0] direction,
//     output logic [DEPTH-1:0] select
// );
//   logic [DEPTH-1:0][DEPTH-1:0] bigger;
//   generate
//     for (genvar i = 0; i < DEPTH; i++) begin
//       for (genvar j = i + 1; j < DEPTH; j++) begin
//         // i older than j
//         assign bigger[i][j] = ((direction[i] ^ direction[j]) ^ (index[i] < index[j]));
//       end
//     end

//     for (genvar i = 0; i < DEPTH; i++) begin
//       assign select[i] = ready[i];
//       for (genvar j = 0; j < DEPTH; j++) begin
//         if (i < j) begin
//           assign select[i] = select[i] & ((~ready[j]) | ready[j] & bigger[i][j]);
//         end else if (i > j) begin
//           assign select[i] = select[i] & ((~ready[j]) | ready[j] & ~bigger[j][i]);
//         end
//       end
//     end
//   endgenerate
// endmodule


// 如果只有一个写端口，那么bigger[i][j] <= (bigger[i][j] & ~(idx[j])) | (idx[i]);
// 如果有多个写端口，并且第一个端口的输入更老，可以将过程为两个部分
// 1. 仍然按照之前的模式进行填充，不考虑这两个写端口之间的影响，如下面第2张表和第4张表
// 2. 构建多个写端口之间的掩码,覆盖在原来的表上
// 0 0 0 0  1 1 1 1  1 0 1 1  1 0 0 0  1 0 0 0
// 0 0 0 0  1 1 1 1  1 1 1 1  1 1 0 0  1 1 0 0
// 0 0 0 0  0 0 0 0  0 0 0 0  1 1 1 1  1 1 1 0
// 0 0 0 0  0 0 0 0  0 0 0 0  1 1 1 1  1 1 1 1
module DirectionSelector #(
    parameter DEPTH = 8,
    parameter WRITE_PORT=1,
    parameter ADDR_WIDTH = $clog2(DEPTH)
) (
    input logic clk,
    input logic rst,
    input logic [WRITE_PORT-1: 0] en,
    input logic [WRITE_PORT-1: 0][DEPTH-1:0] idx,
    input logic [DEPTH-1:0] ready,
    output logic [DEPTH-1:0] select
);
  logic [DEPTH-1:0][DEPTH-1:0] bigger, bigger_mask;

  generate
    for (genvar i = 0; i < DEPTH; i++) begin
      for (genvar j = 0; j < DEPTH; j++) begin
        if(i == j)begin
          assign bigger_mask[i][j] = 1'b1;
        end
        else begin
          assign bigger_mask[i][j] = ~(bigger[i][j] & ready[j]);
        end
      end
      assign select[i] = (&bigger_mask[i]) & ready[i];
    end
  endgenerate

// for multi write port
  logic [WRITE_PORT-1: 0][DEPTH-1: 0] older_valid, idx_valid;
  logic [WRITE_PORT-1: 0][DEPTH-1: 0][DEPTH-1: 0] older_masks;
  logic [DEPTH-1: 0][DEPTH-1: 0][WRITE_PORT-1: 0] older_masks_reverse;
  logic [DEPTH-1: 0] idx_combine;
  logic [DEPTH-1: 0][DEPTH-1: 0] older_mask, bigger_n_pre, bigger_n;
generate
  for(genvar i=0; i<WRITE_PORT-1; i++)begin
    ParallelOR #(DEPTH, WRITE_PORT-1-i) or_older (idx_valid[WRITE_PORT-1: i+1], older_valid[i]);
  end
  assign older_valid[WRITE_PORT-1] = {DEPTH{1'b0}};
  ParallelOR #(DEPTH, WRITE_PORT) or_idx (idx_valid, idx_combine);
  for(genvar i=0; i<WRITE_PORT; i++)begin
    assign idx_valid[i] = {DEPTH{en[i]}} & idx[i];
    for(genvar j=0; j<DEPTH; j++)begin
      for(genvar k=0; k<DEPTH; k++)begin
        assign older_masks[i][j][k] = ~(idx_valid[i][j] & older_valid[i][k]);
        assign older_masks_reverse[j][k][i] = older_masks[i][j][k];
      end
    end
  end

  for(genvar i=0; i<DEPTH; i++)begin
    for(genvar j=0; j<DEPTH; j++)begin
      assign older_mask[i][j] = &older_masks_reverse[i][j];
      assign bigger_n_pre[i][j] = (bigger[i][j] & ~(idx_combine[j])) | (idx_combine[i]);
      assign bigger_n[i][j] = bigger_n_pre[i][j] & older_mask[i][j];
    end
  end
endgenerate

  always_ff @(posedge clk or posedge rst) begin
    if (rst == `RST) begin
      bigger <= 0;
    end else begin
      if (|en) begin
        bigger <= bigger_n;
      end
    end
  end

endmodule

module OrderSelector #(
  parameter BANK_SIZE=4,
  parameter DEPTH=8,
  parameter ADDR_WIDTH=$clog2(DEPTH)
)(
  input logic clk,
  input logic rst,
  input logic [BANK_SIZE-1: 0][ADDR_WIDTH-1: 0] bankNum,
  output logic [BANK_SIZE-1: 0][$clog2(BANK_SIZE)-1: 0] order
);
  logic [BANK_SIZE-1: 0][$clog2(BANK_SIZE)-1: 0] originOrder, sortOrder;
generate
  for(genvar i=0; i<BANK_SIZE; i++)begin
    assign originOrder[i] = i;
  end
endgenerate
  Sort #(BANK_SIZE, ADDR_WIDTH, $clog2(BANK_SIZE)) sort_order (bankNum, originOrder, sortOrder);
  always_ff @(posedge clk)begin
    order <= sortOrder;
  end
endmodule