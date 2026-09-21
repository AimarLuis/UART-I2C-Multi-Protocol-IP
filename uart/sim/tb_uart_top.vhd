library ieee;
use ieee.std_logic_1164.all;

-- Exercises uart_top's host interface directly in both directions.
-- uart_rx/uart_tx's own FSM correctness is already covered exhaustively by
-- tb_uart_rx.vhd/tb_uart_tx.vhd -- this testbench's only job is to prove
-- the top-level wiring (host ports connected to the right internal
-- signals) is correct, so one clean case per direction is enough.
entity tb_uart_top is
end tb_uart_top;

architecture tb of tb_uart_top is

    -- 1. DEVICE-UNDER-TEST COMPONENT DECLARATION
    component uart_top is
        generic (
            clk_freq : integer := 100000000;
            baudrate : integer := 9600
        );
        port (
            clk        : in  std_logic;
            reset_n    : in  std_logic;
            rx_pin_i   : in  std_logic;
            tx_pin_o   : out std_logic;
            tx_start_i : in  std_logic;
            tx_byte_i  : in  std_logic_vector(7 downto 0);
            tx_busy_o  : out std_logic;
            rx_data_o  : out std_logic_vector(7 downto 0);
            rx_done_o  : out std_logic;
            rx_err_o   : out std_logic
        );
    end component;

    -- 2. TESTBENCH SIGNALS
    signal clk        : std_logic := '0';
    signal reset_n     : std_logic := '0';
    signal rx_pin_i    : std_logic := '1'; -- Line idle at '1'
    signal tx_pin_o    : std_logic;
    signal tx_start_i  : std_logic := '0';
    signal tx_byte_i   : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_busy_o   : std_logic;
    signal rx_data_o   : std_logic_vector(7 downto 0);
    signal rx_done_o   : std_logic;
    signal rx_err_o    : std_logic;

    -- Latched outcome of the RX frame currently/last in flight -- rx_done_o
    -- and rx_err_o are single-cycle pulses; p_rx_result_latch below captures
    -- them into level signals p_stimulus can assert against after the fact.
    signal rx_done_latched : std_logic := '0';
    signal rx_err_latched  : std_logic := '0';
    signal rx_data_latched : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_i_prev       : std_logic := '1';

    -- 3. TIME CONSTANTS
    constant CLK_PERIOD : time := 10 ns;        -- 100 MHz master clock
    constant BIT_PERIOD : time := 104.166 us;   -- Bit period at 9600 baud

    constant TX_TEST_BYTE : std_logic_vector(7 downto 0) := x"41"; -- 'A', sent host->line
    constant RX_TEST_BYTE : std_logic_vector(7 downto 0) := x"55"; -- sent line->host, deliberately different

begin

    -- 4. DUT
    dut : uart_top
        port map (
            clk        => clk,
            reset_n    => reset_n,
            rx_pin_i   => rx_pin_i,
            tx_pin_o   => tx_pin_o,
            tx_start_i => tx_start_i,
            tx_byte_i  => tx_byte_i,
            tx_busy_o  => tx_busy_o,
            rx_data_o  => rx_data_o,
            rx_done_o  => rx_done_o,
            rx_err_o   => rx_err_o
        );

    -- 5. MASTER CLOCK GENERATION
    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- 6. RX RESULT LATCH (same technique as tb_uart_rx.vhd)
    p_rx_result_latch : process(clk)
    begin
        if rising_edge(clk) then
            if rx_i_prev = '1' and rx_pin_i = '0' then
                rx_done_latched <= '0';
                rx_err_latched  <= '0';
            elsif rx_done_o = '1' then
                rx_done_latched <= '1';
                rx_data_latched <= rx_data_o;
            elsif rx_err_o = '1' then
                rx_err_latched <= '1';
            end if;
            rx_i_prev <= rx_pin_i;
        end if;
    end process p_rx_result_latch;

    -- 7. TX FRAME CAPTURE AND VERIFICATION (same technique as tb_uart_tx.vhd)
    -- Listens on tx_pin_o, reconstructs the transmitted byte (LSB first) and
    -- compares it against TX_TEST_BYTE -- a byte-by-byte check, not just
    -- timing/waveform inspection.
    p_tx_capture : process
        variable v_byte     : std_logic_vector(7 downto 0);
        variable v_par_tx   : std_logic;
        variable v_par_calc : std_logic;
        variable v_stop     : std_logic;
    begin
        wait until falling_edge(tx_pin_o); -- start of the start bit

        wait for BIT_PERIOD * 1.5; -- center of bit 0 (LSB)
        for i in 0 to 7 loop
            v_byte(i) := tx_pin_o;
            wait for BIT_PERIOD;
        end loop;
        v_par_tx := tx_pin_o; -- center of the parity bit
        wait for BIT_PERIOD;
        v_stop := tx_pin_o; -- center of the stop bit

        v_par_calc := v_byte(0) xor v_byte(1) xor v_byte(2) xor v_byte(3) xor
                      v_byte(4) xor v_byte(5) xor v_byte(6) xor v_byte(7);

        assert v_byte = TX_TEST_BYTE
            report "TX: incorrect transmitted byte" severity error;
        assert v_par_tx = v_par_calc
            report "TX: incorrect transmitted parity" severity error;
        assert v_stop = '1'
            report "TX: incorrect stop bit" severity error;

        if v_byte = TX_TEST_BYTE and v_par_tx = v_par_calc and v_stop = '1' then
            report "TX: host-driven frame verified correctly (byte=0x41)";
        end if;
        wait; -- a single frame in this testbench
    end process p_tx_capture;

    -- 8. STIMULUS: exercises TX and RX independently -- no internal echo
    -- wiring exists in this top, so each direction has to be driven and
    -- checked on its own.
    p_stimulus : process
        procedure send_frame(
            constant data_byte : in std_logic_vector(7 downto 0);
            constant p_bit     : in std_logic;
            constant stop_bit  : in std_logic
        ) is
        begin
            rx_pin_i <= '0'; -- start bit
            wait for BIT_PERIOD;
            for i in 0 to 7 loop
                rx_pin_i <= data_byte(i);
                wait for BIT_PERIOD;
            end loop;
            rx_pin_i <= p_bit;
            wait for BIT_PERIOD;
            rx_pin_i <= stop_bit;
            wait for BIT_PERIOD;
            rx_pin_i <= '1'; -- back to idle
            wait for 2 * BIT_PERIOD;
        end procedure;
    begin
        -- INITIAL RESET
        reset_n  <= '0';
        rx_pin_i <= '1';
        wait for 100 ns;
        reset_n <= '1';
        wait for 10 * CLK_PERIOD;

        -- ==========================================
        -- CASE 1: host drives TX directly (tx_start_i/tx_byte_i), with no
        -- RX activity involved at all.
        -- ==========================================
        report "--- CASE 1: HOST-DRIVEN TX (0x41) ---";
        tx_byte_i  <= TX_TEST_BYTE;
        tx_start_i <= '1';
        wait for CLK_PERIOD;
        tx_start_i <= '0';
        wait until tx_busy_o = '0'; -- wait for the frame to finish transmitting

        -- ==========================================
        -- CASE 2: host observes RX directly (rx_data_o/rx_done_o), with no
        -- TX activity involved at all. Data: 01010101 (four '1's -> even
        -- parity = '0').
        -- ==========================================
        report "--- CASE 2: HOST-OBSERVED RX (0x55) ---";
        send_frame(RX_TEST_BYTE, '0', '1');
        assert rx_done_latched = '1' and rx_err_latched = '0'
            report "CASE 2: expected rx_done_o, got none (or rx_err_o instead)" severity error;
        assert rx_data_latched = RX_TEST_BYTE
            report "CASE 2: rx_data_o did not match the expected byte (0x55)" severity error;
        if rx_done_latched = '1' and rx_err_latched = '0' and rx_data_latched = RX_TEST_BYTE then
            report "CASE 2: host-observed frame verified correctly (0x55)";
        end if;

        report "--- SIMULATION COMPLETE ---";
        wait;
    end process p_stimulus;

end tb;
