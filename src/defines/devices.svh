`ifndef __DEVICES_SVH__
`define __DEVICES_SVH__
`include "global.svh"

`define IRQ_NUM 1

`define IRQ_START           `PADDR_SIZE'h08000000
`define IRQ_END             `PADDR_SIZE'h10000000
`define CLINT_START         `PADDR_SIZE'h08000000
`define CLINT_END           `PADDR_SIZE'h08010000
`define PLIC_START          `PADDR_SIZE'h0c000000
`define PLIC_END            `PADDR_SIZE'h0c001000

`define PERIPHERAL_SIZE 1
`define PERIPHERAL_START    `PADDR_SIZE'h10000000
`define PERIPHERAL_END      `PADDR_SIZE'h10010000
`define UART_START          `PADDR_SIZE'h10000000
`define UART_END            `PADDR_SIZE'h10001000

`define MEM_START           `PADDR_SIZE'h80000000
`define MEM_END             `PADDR_SIZE'hf0000000

typedef struct packed {
    logic [$clog2(`PERIPHERAL_SIZE+2): 0] idx;
    logic [`PADDR_SIZE-1: 0] start_addr;
    logic [`PADDR_SIZE-1: 0] end_addr;
} addr_rule_t;


// uart


/*
* CSR location 
*/
`define RBR_ADR 3'h0
`define THR_ADR 3'h0
`define IER_ADR 3'h1
`define IIR_ADR 3'h2
`define FCR_ADR 3'h2
`define LCR_ADR 3'h3
`define MCR_ADR 3'h4
`define LSR_ADR 3'h5
`define MSR_ADR 3'h6
`define SCR_ADR 3'h7
`define DLL_ADR 3'h0
`define DLM_ADR 3'h1
`define INIT_DL 3



/*
* CSR Definition
*/
typedef struct packed {
    logic [3:0] zeros;             //always zero
    logic       edssi;             //Enable Modem Status Interrupt
    logic       elsi;              //Enable Receiver Line Status Interrupt
    logic       etbei;             //Enable Transmitter Holding Register Empty Interrupt
    logic       erbi;              //Enable Received Data Available Interrupt
} ier_t; //Interrupt Enable Register

typedef struct packed {
    logic [1:0] fifos_enabled;     //FIFOs Enabled
    logic [1:0] zeros;             //always zero
    logic [2:0] interrupt_id;      //Interrupt ID
    logic       interrupt_pending; //'0' when interrupt pending
} iir_t; //Interrupt Ident. Register

typedef enum logic [1:0] {rxtrigger01=2'b00, rxtrigger04=2'b01, rxtrigger08=2'b10, rxtrigger14=2'b11} rxtrigger_t;

typedef struct packed {
    rxtrigger_t rx_trigger;        //Receive trigger
    logic [1:0] reserved;          //reserved
    logic       dma_mode;          //DMA mode select
    logic       tx_rst;            //Transmit FIFO Reset
    logic       rx_rst;            //Receive FIFO Reset
    logic       ena;               //FIFO enabled
} fcr_t; //FIFO Control Register


typedef enum logic       {eps_odd_parity=1'b0, eps_even_parity=1'b1} eps_t;
typedef enum logic [1:0] {wls_5bits=2'b00, wls_6bits=2'b01, wls_7bits=2'b10, wls_8bits=2'b11} wls_t;

typedef struct packed {
    logic       dlab;              //Divisor Latch Access Bit
    logic       set_break;         //Break Control
                                    //  0: normal sout behaviour
                    //  1: force sout to '0'
    logic       stick_parity;      //Stick Parity
                                    //  0: disable stick parity
                    //  1: fixed parity bit
    eps_t       eps;               //Even Parity Select
                                    //  0: Odd parity
                    //  1: Even parity
    logic       pen;               //Parity Enable
                                    //  1: Insert(Tx) and Check(Rx) Parity bit
    logic       stb;               //Number of stop bits
                                    //  0: 1 stop bit
                    //  1: 2 stop bits, except wls=00 1.5 stop bits
    wls_t       wls;               //Word Length Select
                                    //  00: 5bits
                                    //  01: 6bits
                                    //  10: 7bits
                                    //  11: 8bits
} lcr_t; //Line Control Register

typedef struct packed {
    logic [2:0] zeros;             //always zero
    logic       loop;
    logic       out2;
    logic       out1;
    logic       rts;               //Request To Send
    logic       dtr;               //Data Terminal Ready
} mcr_t; //Modem Control Register

typedef struct packed {
    logic       rx_fifo_error;
    logic       temt;              //Transmitter Emtpy
    logic       thre;              //Transmitter Holding Register Empty
    logic       bi;                //Break Interrupt
    logic       fe;                //Framing Error
    logic       pe;                //Parity Error
    logic       oe;                //Overrun Error
    logic       dr;                //Data Ready
} lsr_t; //Line Status Register

typedef struct packed {
    logic       dcd;               //Data Carrier Detect
    logic       ri;                //Ring Indicator
    logic       dsr;               //Data Set Ready
    logic       cts;               //Clear To Send
    logic       ddcd;              //Delta Data Carrier Detect
    logic       teri;              //Trailing Edge Ring Indicator
    logic       ddsr;              //Delta Data Set Ready
    logic       dcts;              //Delta Clear To Send
} msr_t; //Modem Status Register

typedef struct packed {
    logic [7:0] dlm;               //Divisor Latch MSB
    logic [7:0] dll;               //Divisor Latch LSB
} dl_t;

typedef struct {
    ier_t       ier;               //Interrupt Enable Register
    iir_t       iir;               //Interrupt Ident. Register
    fcr_t       fcr;               //FIFO Control Register
    lcr_t       lcr;               //Line Control Register
    lsr_t       lsr;               //Line Status Register
    mcr_t       mcr;               //Modem Control Register
    msr_t       msr;               //Modem Status Register
    logic [7:0] scr;               //Scratch Register
    //dl_t        dl;                //Divisor Latch -- Separate to make Verilator happy
} csr_t;



//Rx FIFO data
typedef struct packed {
    logic       bi;
    logic       fe;
    logic       pe;
    logic [7:0] d;
} rx_d_t;
`endif