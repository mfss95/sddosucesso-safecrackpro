// =============================================================================
// SafeCrackPro - FSM  
// CIN0130 - Sistemas Digitais - Projeto Final 2026.2
// Alunos: 
// Carlos Henrique da Silva Cunha <chsc>
// Livia Clarissa Goncalves Alexandrino <lcga> 
// Lucas Matheus do Carmo <lmc8> 
// Maria Fernanda Soares dos Santos <mfss>
// Vinicius Luiz da Fonseca Santos <vlfs2>
// =============================================================================
// Botoes da DE2-115 (Ativo com o 0 for pressionado)
//   KEY[0] -> rstn   : reset (volta ao inicio a qualquer momento)
//   KEY[1] -> btn[0] : confirma o digito e avanca
//   KEY[2] -> btn[1] : seta direita (+1)
//   KEY[3] -> btn[2] : seta esquerda (-1)
//
// Organizacao (Seguindo o padrao do SafeCrack base)
//   1) always_comb -> deteccao de borda dos botoes
//   2) always_ff   -> memoria (estado, digitos, posicao, contador)
//   3) always_comb -> regras de transicao
//   4) always_comb -> saidas (LEDs)
// =============================================================================

module safecrackpro_fsm #(
    // Deixamos a senha e os tempos como parametros para que fique tudo
    // configurado em um lugar so, no inicio do modulo.

    // Senha do cofre. A especificacao sugere defini ela como parametro.
    // Escrevemos em hexadecimal porque cada digito hex ocupa 4 bits, entao
    // 16'h1234 vai ler direto como a senha 1-2-3-4 (HEX3=1, HEX2=2, HEX1=3, HEX0=4).
    // Para trocar a senha so precisaremos mudar esse valor, por exemplo 16'h2580.
    parameter logic [15:0] PASSWORD = 16'h1234,

    // Tempo dos LEDs em ciclos de clock. Como o clock da placa e de 50 MHz,
    // 1 segundo corresponde a 50.000.000 ciclos.
    // O tamanho do contador e calculado a partir do tempo verde, por isso
    // ele precisa ser o maior dos dois.
    parameter int          GREEN_LED_CYCLES = 5 * 50_000_000,  // 5 s
    parameter int          RED_LED_CYCLES   = 3 * 50_000_000   // 3 s
)(
    // Usamos as mesmas portas que o top e o testbench do professor esperam.
    input  logic            clk,                  // clock de 50 MHz
    input  logic            rstn,                 // KEY[0], ativo em 0
    input  logic [2:0]      btn,                  // KEY[3:1], ativos em 0
    output logic [3:0][3:0] digits,               // digits[0] = 1o digito (HEX3) ... digits[3] = 4o (HEX0)
    output logic [1:0]      current_position_idx, // digito ativo (0 a 3); o top soma 1 para mostrar no HEX4
    output logic [17:0]     led_red,              // 18 LEDs vermelhos
    output logic [8:0]      led_green             // 9 LEDs verdes
);

    // =========================================================================
    // ESTADOS
    // =========================================================================
    // Usamos codificacao one-hot, como no SafeCrack visto em aula, e os nomes
    // de estado que aparecem nos comentarios do testbench do professor.
    // Optamos por deixar cada acao (incrementar, decrementar, avancar) em um
    // estado proprio de 1 ciclo. Assim cada estado faz uma coisa so, e fica
    // mais facil acompanhar o funcionamento na simulacao.
    typedef enum logic [7:0] {
        START               = 8'b0000_0001, // zera digitos e posicao
        CURRENT_POSITION    = 8'b0000_0010, // espera um botao
        INC_DIGIT           = 8'b0000_0100, // digito + 1 (9 vira 0)
        DEC_DIGIT           = 8'b0000_1000, // digito - 1 (0 vira 9)
        INC_POSITION        = 8'b0001_0000, // confirma e avanca
        CHECK_PASSWORD      = 8'b0010_0000, // compara com a senha
        WAIT_GREEN_LED_TIME = 8'b0100_0000, // senha certa: verdes por 5 s
        WAIT_RED_LED_TIME   = 8'b1000_0000  // senha errada: vermelhos por 3 s
    } state_t;

    state_t state, next_state;

    // =========================================================================
    // SINAIS INTERNOS
    // =========================================================================
    // Codigos de cada botao depois da deteccao de borda. Cada um tem so um bit
    // em 1, porque a FSM aceita apenas um botao por vez.
    localparam logic [2:0] BTN_CONFIRM = 3'b001; // KEY[1]
    localparam logic [2:0] BTN_INC     = 3'b010; // KEY[2]
    localparam logic [2:0] BTN_DEC     = 3'b100; // KEY[3]

    logic [2:0] btn_pos;   // botoes invertidos (1 = apertado)
    logic [2:0] btn_prev;  // valor dos botoes no ciclo anterior
    logic [2:0] btn_edge;  // pulso de 1 ciclo quando o botao e apertado

    // Proximo valor dos digitos e da posicao, calculados nas regras (bloco 3).
    logic [3:0][3:0] next_digits;
    logic [1:0]      next_position_idx;

    // Contador para o tempo dos LEDs, parecido com o delay_cnt do SafeCrack
    // de aula. Usamos $clog2 para calcular quantos bits ele precisa (28 bits
    // para 250 milhoes de ciclos).
    // Fizemos o contador decrescente: ele comeca no tempo total e diminui ate 0,
    // e 0 significa que o tempo acabou. 
    logic [$clog2(GREEN_LED_CYCLES)-1:0] led_time_cnt, next_led_time_cnt;

    // Verificacao da senha. Comparamos digito por digito porque a ordem nao e
    // a mesma: no PASSWORD o primeiro digito fica nos bits mais altos (15:12),
    // enquanto em digits ele fica na posicao [0].
    logic password_ok;
    assign password_ok = (digits[0] == PASSWORD[15:12]) &&  // 1o digito
                         (digits[1] == PASSWORD[11:8])  &&  // 2o digito
                         (digits[2] == PASSWORD[7:4])   &&  // 3o digito
                         (digits[3] == PASSWORD[3:0]);      // 4o digito

    // Valor do digito que esta sendo editado no momento. Criamos esse sinal
    // para nao repetir digits[current_position_idx] nas regras de incremento
    // e decremento.
    logic [3:0] active_digit;
    assign active_digit = digits[current_position_idx];

    // =========================================================================
    // 1) DETECCAO DE BORDA  (combinacional)
    // =========================================================================
    // Mesma tecnica do SafeCrack de aula. Comparamos o botao agora com o valor
    // do ciclo anterior, e btn_edge so fica em 1 no primeiro ciclo do aperto.
    // Com isso, segurar o botao gera uma unica acao, como pede a especificacao.
    always_comb begin
        btn_pos  = ~btn;                 // botoes da placa sao ativos em 0
        btn_edge = btn_pos & ~btn_prev;  // apertado agora e solto antes
    end

    // =========================================================================
    // 2) REGISTRADORES  (sequencial)
    // =========================================================================
    // Seguimos a estrutura do SafeCrack de aula, com reset assincrono: ao
    // apertar KEY[0], o sistema volta ao inicio na hora, em qualquer estado.
    // Os valores de reset sao os que a especificacao pede: displays em 0,
    // primeiro digito ativo e LEDs apagados (START nao acende nenhum LED).
    always_ff @(posedge clk or negedge rstn) begin
        if (~rstn) begin
            state                <= START;
            btn_prev             <= 3'b000;  // considera os botoes soltos
            digits               <= 16'd0;   // displays em 0
            current_position_idx <= 2'd0;    // primeiro digito ativo
            led_time_cnt         <= 0;
        end
        else begin
            state                <= next_state;
            btn_prev             <= btn_pos;  // guarda para comparar no proximo ciclo
            digits               <= next_digits;
            current_position_idx <= next_position_idx;
            led_time_cnt         <= next_led_time_cnt;
        end
    end

    // =========================================================================
    // 3) REGRAS DE TRANSICAO  (combinacional)
    // =========================================================================
    always_comb begin
        // Por padrao, tudo continua igual. Cada estado so altera o que precisa,
        // e assim evitamos a criacao de memoria extra.
        next_state        = state;
        next_digits       = digits;
        next_position_idx = current_position_idx;
        next_led_time_cnt = led_time_cnt;

        unique case (state)

            // Estado inicial. Voltamos para ca depois do reset e tambem depois
            // do tempo dos LEDs, entao aqui zeramos tudo para uma nova tentativa.
            START: begin
                next_digits       = 16'd0;
                next_position_idx = 2'd0;
                next_led_time_cnt = 0;
                next_state        = CURRENT_POSITION;
            end

            // Esperamos um botao. Olhamos btn_edge, e nao o botao direto, para
            // que segurar o botao nao repita a acao. Se nenhum botao for
            // apertado, ou se dois forem apertados juntos, a FSM continua aqui.
            CURRENT_POSITION: begin
                case (btn_edge)
                    BTN_CONFIRM: next_state = INC_POSITION;
                    BTN_INC:     next_state = INC_DIGIT;
                    BTN_DEC:     next_state = DEC_DIGIT;
                    default:     next_state = CURRENT_POSITION;
                endcase
            end

            // Seta para a direita: soma 1 no digito ativo. Quando o digito e 9,
            // volta para 0 (wrap-around). Os outros digitos nao sao alterados.
            INC_DIGIT: begin
                next_digits[current_position_idx] = (active_digit == 4'd9) ? 4'd0
                                                                           : active_digit + 4'd1;
                next_state = CURRENT_POSITION;
            end

            // Seta para a esquerda: subtrai 1 no digito ativo. Quando o digito
            // e 0, vai para 9.
            DEC_DIGIT: begin
                next_digits[current_position_idx] = (active_digit == 4'd0) ? 4'd9
                                                                           : active_digit - 4'd1;
                next_state = CURRENT_POSITION;
            end

            // Confirmacao: passamos para o proximo digito. A posicao so aumenta,
            // entao nao tem como voltar para um digito ja confirmado (para isso
            // o usuario usa o reset). Se ja estava no 4o digito, a senha
            // esta completa e vamos para a verificacao.
            INC_POSITION: begin
                if (current_position_idx == 2'd3) begin
                    next_state = CHECK_PASSWORD;
                end else begin
                    next_position_idx = current_position_idx + 2'd1;
                    next_state        = CURRENT_POSITION;
                end
            end

            // Verificamos a senha e carregamos o contador com o tempo do LED
            // correspondente. Carregamos N-1 porque a contagem vai ate 0,
            // entao de N-1 ate 0 sao exatamente N ciclos.
            CHECK_PASSWORD: begin
                if (password_ok) begin
                    next_led_time_cnt = GREEN_LED_CYCLES - 1; // 5 s
                    next_state        = WAIT_GREEN_LED_TIME;
                end else begin
                    next_led_time_cnt = RED_LED_CYCLES - 1;   // 3 s
                    next_state        = WAIT_RED_LED_TIME;
                end
            end

            // Senha correta: os LEDs verdes ficam acesos enquanto o contador
            // desce. Nesse estado os botoes nao tem efeito (so o reset).
            // Quando o tempo acaba, ja zeramos os digitos na transicao para que
            // os displays voltem a 0 junto com o retorno ao inicio.
            WAIT_GREEN_LED_TIME: begin
                if (led_time_cnt != 0) begin
                    next_led_time_cnt = led_time_cnt - 1;
                end else begin
                    next_digits       = 16'd0;
                    next_position_idx = 2'd0;
                    next_state        = START;
                end
            end

            // Senha incorreta: mesma logica, com os LEDs vermelhos.
            WAIT_RED_LED_TIME: begin
                if (led_time_cnt != 0) begin
                    next_led_time_cnt = led_time_cnt - 1;
                end else begin
                    next_digits       = 16'd0;
                    next_position_idx = 2'd0;
                    next_state        = START;
                end
            end

            // Se a FSM cair em um estado invalido, volta para o inicio.
            default: next_state = START;
        endcase
    end

    // =========================================================================
    // 4) SAIDAS  (combinacional, Moore)
    // =========================================================================
    // Os LEDs dependem apenas do estado atual, entao ficam acesos durante
    // todo o tempo de espera. Acendemos todos os LEDs da cor
    // correspondente: 9'h1FF sao os 9 verdes e 18'h3FFFF os 18 vermelhos.
    always_comb begin
        led_green = (state == WAIT_GREEN_LED_TIME) ? 9'h1FF    : 9'h000;
        led_red   = (state == WAIT_RED_LED_TIME)   ? 18'h3FFFF : 18'h00000;
    end

endmodule
