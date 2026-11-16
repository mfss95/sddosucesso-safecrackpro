// =============================================================================
// SafeCrackPro - Modulo TOP
// Liga a FSM (safecrackpro_fsm) aos 5 decodificadores BCD -> 7 segmentos.
// Os nomes das portas sao os mesmos de quartus/pin_assignments.txt.
// =============================================================================
module safecrackpro_top (
    input  logic        clk,          // CLOCK_50 (50 MHz)
    input  logic        rstn,         // KEY[0] - reset (ativo baixo)
    input  logic [2:0]  btn,          // KEY[3:1] - {esquerda, direita, confirma} (ativos baixo)
    output logic [6:0]  seg_pos1,     // HEX3 - 1º dígito da senha (digits[0])
    output logic [6:0]  seg_pos2,     // HEX2 - 2º dígito (digits[1])
    output logic [6:0]  seg_pos3,     // HEX1 - 3º dígito (digits[2])
    output logic [6:0]  seg_pos4,     // HEX0 - 4º dígito (digits[3])
    output logic [6:0]  seg_cur_pos,  // HEX4 - índice do dígito ativo (1 a 4)
    output logic [17:0] led_red,      // LEDR[17:0] - senha errada
    output logic [8:0]  led_green     // LEDG[8:0]  - senha correta
);

    logic [3:0][3:0] digits;    // os 4 dígitos guardados pela FSM
    logic [1:0]      position;  // dígito ativo (0 a 3)

    // O nome "fsm_inst" é usado pelo testbench (dut.fsm_inst.led_time_cnt).
    safecrackpro_fsm fsm_inst (
        .clk                  (clk),
        .rstn                 (rstn),
        .btn                  (btn),
        .digits               (digits),
        .current_position_idx (position),
        .led_red              (led_red),
        .led_green            (led_green)
    );

    bcd_to_7segment_anodo dec_pos1 (
        .bcd (digits[0]),
        .seg (seg_pos1)
    );

    bcd_to_7segment_anodo dec_pos2 (
        .bcd (digits[1]),
        .seg (seg_pos2)
    );

    bcd_to_7segment_anodo dec_pos3 (
        .bcd (digits[2]),
        .seg (seg_pos3)
    );

    bcd_to_7segment_anodo dec_pos4 (
        .bcd (digits[3]),
        .seg (seg_pos4)
    );

    // A FSM conta as posições de 0 a 3; somamos 1 para o HEX4 mostrar 1 a 4.
    bcd_to_7segment_anodo dec_cur_pos (
        .bcd ({2'b00, position} + 4'd1),
        .seg (seg_cur_pos)
    );

endmodule
