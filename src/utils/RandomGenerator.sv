`include "../defines/defines.svh"

module LFSRRandom #(
    parameter WIDTH = 32,
    parameter SEED = 0
)(
    input logic clk,
    input logic rst,
    output logic [WIDTH-1: 0] random
);
    logic lfsr_fb;
generate;
  case (WIDTH-1)   
    2      : assign lfsr_fb = ~(random[2  ]^random[1  ]                                );
    3      : assign lfsr_fb = ~(random[3  ]^random[2  ]                                );
    4      : assign lfsr_fb = ~(random[4  ]^random[3  ]                                );
    5      : assign lfsr_fb = ~(random[5  ]^random[3  ]                                );
    6      : assign lfsr_fb = ~(random[6  ]^random[5  ]                                );
    7      : assign lfsr_fb = ~(random[7  ]^random[6  ]                                );
    8      : assign lfsr_fb = ~(random[8  ]^random[6  ]^random[5  ]^random[4  ]              );
    9      : assign lfsr_fb = ~(random[9  ]^random[5  ]                                );
    10     : assign lfsr_fb = ~(random[10 ]^random[7  ]                                );
    11     : assign lfsr_fb = ~(random[11 ]^random[9  ]                                );
    12     : assign lfsr_fb = ~(random[12 ]^random[6  ]^random[4  ]^random[1  ]              );
    13     : assign lfsr_fb = ~(random[13 ]^random[4  ]^random[3  ]^random[1  ]              );
    14     : assign lfsr_fb = ~(random[14 ]^random[5  ]^random[3  ]^random[1  ]              );
    15     : assign lfsr_fb = ~(random[15 ]^random[14 ]                                );
    16     : assign lfsr_fb = ~(random[16 ]^random[15 ]^random[13 ]^random[4  ]              );
    17     : assign lfsr_fb = ~(random[17 ]^random[14 ]                                );
    18     : assign lfsr_fb = ~(random[18 ]^random[11 ]                                );
    19     : assign lfsr_fb = ~(random[19 ]^random[6  ]^random[2  ]^random[1  ]              );
    20     : assign lfsr_fb = ~(random[20 ]^random[17 ]                                );
    21     : assign lfsr_fb = ~(random[21 ]^random[19 ]                                );
    22     : assign lfsr_fb = ~(random[22 ]^random[21 ]                                );
    23     : assign lfsr_fb = ~(random[23 ]^random[18 ]                                );
    24     : assign lfsr_fb = ~(random[24 ]^random[23 ]^random[22 ]^random[17 ]              );
    25     : assign lfsr_fb = ~(random[25 ]^random[22 ]                                );
    26     : assign lfsr_fb = ~(random[26 ]^random[6  ]^random[2  ]^random[1  ]              );
    27     : assign lfsr_fb = ~(random[27 ]^random[5  ]^random[2  ]^random[1  ]              );
    28     : assign lfsr_fb = ~(random[28 ]^random[25 ]                                );
    29     : assign lfsr_fb = ~(random[29 ]^random[27 ]                                );
    30     : assign lfsr_fb = ~(random[30 ]^random[6  ]^random[4  ]^random[1  ]              );
    31     : assign lfsr_fb = ~(random[31 ]^random[28 ]                                );
    32     : assign lfsr_fb = ~(random[32 ]^random[22 ]^random[2  ]^random[1  ]              );
    33     : assign lfsr_fb = ~(random[33 ]^random[20 ]                                );
    34     : assign lfsr_fb = ~(random[34 ]^random[27 ]^random[2  ]^random[1  ]              );
    35     : assign lfsr_fb = ~(random[35 ]^random[33 ]                                );
    36     : assign lfsr_fb = ~(random[36 ]^random[25 ]                                );
    37     : assign lfsr_fb = ~(random[37 ]^random[5  ]^random[4  ]^random[3  ]^random[2]^random[1]);
    38     : assign lfsr_fb = ~(random[38 ]^random[6  ]^random[5  ]^random[1  ]              );
    39     : assign lfsr_fb = ~(random[39 ]^random[35 ]                                );
    40     : assign lfsr_fb = ~(random[40 ]^random[38 ]^random[21 ]^random[19 ]              );
    41     : assign lfsr_fb = ~(random[41 ]^random[38 ]                                );
    42     : assign lfsr_fb = ~(random[42 ]^random[41 ]^random[20 ]^random[19 ]              );
    43     : assign lfsr_fb = ~(random[43 ]^random[42 ]^random[38 ]^random[37 ]              );
    44     : assign lfsr_fb = ~(random[44 ]^random[43 ]^random[18 ]^random[17 ]              );
    45     : assign lfsr_fb = ~(random[45 ]^random[44 ]^random[42 ]^random[41 ]              );
    46     : assign lfsr_fb = ~(random[46 ]^random[45 ]^random[26 ]^random[25 ]              );
    47     : assign lfsr_fb = ~(random[47 ]^random[42 ]                                );
    48     : assign lfsr_fb = ~(random[48 ]^random[47 ]^random[21 ]^random[20 ]              );
    49     : assign lfsr_fb = ~(random[49 ]^random[40 ]                                );
    50     : assign lfsr_fb = ~(random[50 ]^random[49 ]^random[24 ]^random[23 ]              );
    51     : assign lfsr_fb = ~(random[51 ]^random[50 ]^random[36 ]^random[35 ]              );
    52     : assign lfsr_fb = ~(random[52 ]^random[49 ]                                );
    53     : assign lfsr_fb = ~(random[53 ]^random[52 ]^random[38 ]^random[37 ]              );
    54     : assign lfsr_fb = ~(random[54 ]^random[53 ]^random[18 ]^random[17 ]              );
    55     : assign lfsr_fb = ~(random[55 ]^random[31 ]                                );
    56     : assign lfsr_fb = ~(random[56 ]^random[55 ]^random[35 ]^random[34 ]              );
    57     : assign lfsr_fb = ~(random[57 ]^random[50 ]                                );
    58     : assign lfsr_fb = ~(random[58 ]^random[39 ]                                );
    59     : assign lfsr_fb = ~(random[59 ]^random[58 ]^random[38 ]^random[37 ]              );
    60     : assign lfsr_fb = ~(random[60 ]^random[59 ]                                );
    61     : assign lfsr_fb = ~(random[61 ]^random[60 ]^random[46 ]^random[45 ]              );
    62     : assign lfsr_fb = ~(random[62 ]^random[61 ]^random[6  ]^random[5  ]              );
    63     : assign lfsr_fb = ~(random[63 ]^random[62 ]                                );
    64     : assign lfsr_fb = ~(random[64 ]^random[63 ]^random[61 ]^random[60 ]              );
    65     : assign lfsr_fb = ~(random[65 ]^random[47 ]                                );
    66     : assign lfsr_fb = ~(random[66 ]^random[65 ]^random[57 ]^random[56 ]              );
    67     : assign lfsr_fb = ~(random[67 ]^random[66 ]^random[58 ]^random[57 ]              );
    68     : assign lfsr_fb = ~(random[68 ]^random[59 ]                                );
    69     : assign lfsr_fb = ~(random[69 ]^random[67 ]^random[42 ]^random[40 ]              );
    70     : assign lfsr_fb = ~(random[70 ]^random[69 ]^random[55 ]^random[54 ]              );
    71     : assign lfsr_fb = ~(random[71 ]^random[65 ]                                );
    72     : assign lfsr_fb = ~(random[72 ]^random[66 ]^random[25 ]^random[19 ]              );
    73     : assign lfsr_fb = ~(random[73 ]^random[48 ]                                );
    74     : assign lfsr_fb = ~(random[74 ]^random[73 ]^random[59 ]^random[58 ]              );
    75     : assign lfsr_fb = ~(random[75 ]^random[74 ]^random[65 ]^random[64 ]              );
    76     : assign lfsr_fb = ~(random[76 ]^random[75 ]^random[41 ]^random[40 ]              );
    77     : assign lfsr_fb = ~(random[77 ]^random[76 ]^random[47 ]^random[46 ]              );
    78     : assign lfsr_fb = ~(random[78 ]^random[77 ]^random[59 ]^random[58 ]              );
    79     : assign lfsr_fb = ~(random[79 ]^random[70 ]                                );
    80     : assign lfsr_fb = ~(random[80 ]^random[79 ]^random[43 ]^random[42 ]              );
    81     : assign lfsr_fb = ~(random[81 ]^random[77 ]                                );
    82     : assign lfsr_fb = ~(random[82 ]^random[79 ]^random[47 ]^random[44 ]              );
    83     : assign lfsr_fb = ~(random[83 ]^random[82 ]^random[38 ]^random[37 ]              );
    84     : assign lfsr_fb = ~(random[84 ]^random[71 ]                                );
    85     : assign lfsr_fb = ~(random[85 ]^random[84 ]^random[58 ]^random[57 ]              );
    86     : assign lfsr_fb = ~(random[86 ]^random[85 ]^random[74 ]^random[73 ]              );
    87     : assign lfsr_fb = ~(random[87 ]^random[74 ]                                );
    88     : assign lfsr_fb = ~(random[88 ]^random[87 ]^random[17 ]^random[16 ]              );
    89     : assign lfsr_fb = ~(random[89 ]^random[51 ]                                );
    90     : assign lfsr_fb = ~(random[90 ]^random[89 ]^random[72 ]^random[71 ]              );
    91     : assign lfsr_fb = ~(random[91 ]^random[90 ]^random[8  ]^random[7  ]              );
    92     : assign lfsr_fb = ~(random[92 ]^random[91 ]^random[80 ]^random[79 ]              );
    93     : assign lfsr_fb = ~(random[93 ]^random[91 ]                                );
    94     : assign lfsr_fb = ~(random[94 ]^random[73 ]                                );
    95     : assign lfsr_fb = ~(random[95 ]^random[84 ]                                );
    96     : assign lfsr_fb = ~(random[96 ]^random[94 ]^random[49 ]^random[47 ]              );
    97     : assign lfsr_fb = ~(random[97 ]^random[91 ]                                );
    98     : assign lfsr_fb = ~(random[98 ]^random[87 ]                                );
    99     : assign lfsr_fb = ~(random[99 ]^random[97 ]^random[54 ]^random[52 ]              );
    100    : assign lfsr_fb = ~(random[100]^random[63 ]                                );
    101    : assign lfsr_fb = ~(random[101]^random[100]^random[95 ]^random[94 ]              );
    102    : assign lfsr_fb = ~(random[102]^random[101]^random[36 ]^random[35 ]              );
    103    : assign lfsr_fb = ~(random[103]^random[94 ]                                );
    104    : assign lfsr_fb = ~(random[104]^random[103]^random[94 ]^random[93 ]              );
    105    : assign lfsr_fb = ~(random[105]^random[89 ]                                );
    106    : assign lfsr_fb = ~(random[106]^random[91 ]                                );
    107    : assign lfsr_fb = ~(random[107]^random[105]^random[44 ]^random[42 ]              );
    108    : assign lfsr_fb = ~(random[108]^random[77 ]                                );
    109    : assign lfsr_fb = ~(random[109]^random[108]^random[103]^random[102]              );
    110    : assign lfsr_fb = ~(random[110]^random[109]^random[98 ]^random[97 ]              );
    111    : assign lfsr_fb = ~(random[111]^random[101]                                );
    112    : assign lfsr_fb = ~(random[112]^random[110]^random[69 ]^random[67 ]              );
    113    : assign lfsr_fb = ~(random[113]^random[104]                                );
    114    : assign lfsr_fb = ~(random[114]^random[113]^random[33 ]^random[32 ]              );
    115    : assign lfsr_fb = ~(random[115]^random[114]^random[101]^random[100]              );
    116    : assign lfsr_fb = ~(random[116]^random[115]^random[46 ]^random[45 ]              );
    117    : assign lfsr_fb = ~(random[117]^random[115]^random[99 ]^random[97 ]              );
    118    : assign lfsr_fb = ~(random[118]^random[85 ]                                );
    119    : assign lfsr_fb = ~(random[119]^random[111]                                );
    120    : assign lfsr_fb = ~(random[120]^random[113]^random[9  ]^random[2  ]              );
    121    : assign lfsr_fb = ~(random[121]^random[103]                                );
    122    : assign lfsr_fb = ~(random[122]^random[121]^random[63 ]^random[62 ]              );
    123    : assign lfsr_fb = ~(random[123]^random[121]                                );
    124    : assign lfsr_fb = ~(random[124]^random[87 ]                                );
    125    : assign lfsr_fb = ~(random[125]^random[124]^random[18 ]^random[17 ]              );
    126    : assign lfsr_fb = ~(random[126]^random[125]^random[90 ]^random[89 ]              );
    127    : assign lfsr_fb = ~(random[127]^random[126]                                );
    128    : assign lfsr_fb = ~(random[128]^random[126]^random[101]^random[99 ]              );
    129    : assign lfsr_fb = ~(random[129]^random[124]                                );
    130    : assign lfsr_fb = ~(random[130]^random[127]                                );
    131    : assign lfsr_fb = ~(random[131]^random[130]^random[84 ]^random[83 ]              );
    132    : assign lfsr_fb = ~(random[132]^random[103]                                );
    133    : assign lfsr_fb = ~(random[133]^random[132]^random[82 ]^random[81 ]              );
    134    : assign lfsr_fb = ~(random[134]^random[77 ]                                );
    135    : assign lfsr_fb = ~(random[135]^random[124]                                );
    136    : assign lfsr_fb = ~(random[136]^random[135]^random[11 ]^random[10 ]              );
    137    : assign lfsr_fb = ~(random[137]^random[116]                                );
    138    : assign lfsr_fb = ~(random[138]^random[137]^random[131]^random[130]              );
    139    : assign lfsr_fb = ~(random[139]^random[136]^random[134]^random[131]              );
    140    : assign lfsr_fb = ~(random[140]^random[111]                                );
    141    : assign lfsr_fb = ~(random[141]^random[140]^random[110]^random[109]              );
    142    : assign lfsr_fb = ~(random[142]^random[121]                                );
    143    : assign lfsr_fb = ~(random[143]^random[142]^random[123]^random[122]              );
    144    : assign lfsr_fb = ~(random[144]^random[143]^random[75 ]^random[74 ]              );
    145    : assign lfsr_fb = ~(random[145]^random[93 ]                                );
    146    : assign lfsr_fb = ~(random[146]^random[145]^random[87 ]^random[86 ]              );
    147    : assign lfsr_fb = ~(random[147]^random[146]^random[110]^random[109]              );
    148    : assign lfsr_fb = ~(random[148]^random[121]                                );
    149    : assign lfsr_fb = ~(random[149]^random[148]^random[40 ]^random[39 ]              );
    150    : assign lfsr_fb = ~(random[150]^random[97 ]                                );
    151    : assign lfsr_fb = ~(random[151]^random[148]                                );
    152    : assign lfsr_fb = ~(random[152]^random[151]^random[87 ]^random[86 ]              );
    153    : assign lfsr_fb = ~(random[153]^random[152]                                );
    154    : assign lfsr_fb = ~(random[154]^random[152]^random[27 ]^random[25 ]              );
    155    : assign lfsr_fb = ~(random[155]^random[154]^random[124]^random[123]              );
    156    : assign lfsr_fb = ~(random[156]^random[155]^random[41 ]^random[40 ]              );
    157    : assign lfsr_fb = ~(random[157]^random[156]^random[131]^random[130]              );
    158    : assign lfsr_fb = ~(random[158]^random[157]^random[132]^random[131]              );
    159    : assign lfsr_fb = ~(random[159]^random[128]                                );
    160    : assign lfsr_fb = ~(random[160]^random[159]^random[142]^random[141]              );
    161    : assign lfsr_fb = ~(random[161]^random[143]                                );
    162    : assign lfsr_fb = ~(random[162]^random[161]^random[75 ]^random[74 ]              );
    163    : assign lfsr_fb = ~(random[163]^random[162]^random[104]^random[103]              );
    164    : assign lfsr_fb = ~(random[164]^random[163]^random[151]^random[150]              );
    165    : assign lfsr_fb = ~(random[165]^random[164]^random[135]^random[134]              );
    166    : assign lfsr_fb = ~(random[166]^random[165]^random[128]^random[127]              );
    167    : assign lfsr_fb = ~(random[167]^random[161]                                );
    168    : assign lfsr_fb = ~(random[168]^random[166]^random[153]^random[151]              );
	 default: assign lfsr_fb = 1'bx                                                ;
  endcase
endgenerate

    always_ff @(posedge clk or negedge rst)begin
        if(rst == `RST)begin
            random <= SEED;
        end
        else begin
            random <= {random[WIDTH-2: 0], lfsr_fb};
        end
    end
endmodule