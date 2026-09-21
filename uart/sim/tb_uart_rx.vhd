library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_uart_rx is
end tb_uart_rx;

architecture tb of tb_uart_rx is

    -- 1. COMPONENTS
    component cnt is
        generic (
            clk_freq  : integer := 100000000;
            baudrate  : integer := 9600
        );
        port (
            clk       : in std_logic;
            reset_n   : in std_logic;
            tick_16_o : out std_logic
        );
    end component;

    component uart_rx is
        port (
            clk           : in  std_logic;
            reset_n       : in  std_logic;
            rx_i          : in  std_logic;
            tick_16_i     : in  std_logic;
            rx_data_o     : out std_logic_vector(7 downto 0);
            rx_done_o     : out std_logic;
            rx_err_o      : out std_logic
        );
    end component;

    -- 2. INTERNAL SIGNALS
    signal tb_clk       : std_logic := '0';
    signal tb_reset_n   : std_logic := '0';
    signal tb_rx_i      : std_logic := '1'; -- Line idle at '1'
    signal tb_tick_16   : std_logic;

    signal tb_rx_data   : std_logic_vector(7 downto 0);
    signal tb_rx_done   : std_logic;
    signal tb_rx_err    : std_logic;

    -- Latched outcome of the frame currently/last in flight -- rx_done_o and
    -- rx_err_o are single-cycle pulses, so p_result_latch below captures
    -- them into level signals p_stimulus can assert against after the fact.
    signal tb_done_latched : std_logic := '0';
    signal tb_err_latched  : std_logic := '0';
    signal tb_data_latched : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_i_prev       : std_logic := '1';

    constant CLK_PERIOD : time := 10 ns;
    constant BIT_PERIOD : time := 104166 ns; -- 1 bit at 9600 baud

begin

    -- Clears the latches on every new start bit (falling edge on rx_i) and
    -- captures rx_done_o/rx_err_o whenever either pulses, so each case's
    -- outcome survives long enough for p_stimulus to assert against it.
    p_result_latch : process(tb_clk)
    begin
        if rising_edge(tb_clk) then
            if rx_i_prev = '1' and tb_rx_i = '0' then
                tb_done_latched <= '0';
                tb_err_latched  <= '0';
            elsif tb_rx_done = '1' then
                tb_done_latched <= '1';
                tb_data_latched <= tb_rx_data;
            elsif tb_rx_err = '1' then
                tb_err_latched <= '1';
            end if;
            rx_i_prev <= tb_rx_i;
        end if;
    end process p_result_latch;

    -- 3. MASTER CLOCK
    tb_clk <= not tb_clk after CLK_PERIOD/2;

    -- 4. BAUD RATE GENERATOR (DUT 1)
    u_baud_gen : cnt
        port map (
            clk       => tb_clk,
            reset_n   => tb_reset_n,
            tick_16_o => tb_tick_16
        );

    -- 5. UART RECEIVER (DUT 2)
    u_rx : uart_rx
        port map (
            clk           => tb_clk,
            reset_n       => tb_reset_n,
            rx_i          => tb_rx_i,
            tick_16_i     => tb_tick_16,
            rx_data_o     => tb_rx_data,
            rx_done_o     => tb_rx_done,
            rx_err_o      => tb_rx_err
        );

    -- 6. STIMULUS CHOREOGRAPHY (Test Cases)
    p_stimulus : process
        -- Internal procedure to inject physical frames on the rx_i line
        procedure send_frame(
            constant data_byte : in std_logic_vector(7 downto 0);
            constant p_bit     : in std_logic;
            constant stop_bit  : in std_logic
        ) is
        begin
            -- Start Bit
            tb_rx_i <= '0';
            wait for BIT_PERIOD;

            -- 8 Data Bits (sent LSB first)
            for i in 0 to 7 loop
                tb_rx_i <= data_byte(i);
                wait for BIT_PERIOD;
            end loop;

            -- Parity Bit
            tb_rx_i <= p_bit;
            wait for BIT_PERIOD;

            -- Stop Bit
            tb_rx_i <= stop_bit;
            wait for BIT_PERIOD;

            -- Back to idle
            tb_rx_i <= '1';
            wait for 2 * BIT_PERIOD; -- Extra spacing between frames
        end procedure;

    begin
        -- INITIAL RESET
        tb_reset_n <= '0';
        tb_rx_i    <= '1';
        wait for 10 * CLK_PERIOD;
        wait until falling_edge(tb_clk);
        tb_reset_n <= '1';
        wait for 100 * CLK_PERIOD;

        -- ==========================================
        -- CASE 1: Good frame (letter 'A' -> x41)
        -- Data: 01000001 (two '1's -> even parity = '0')
        -- ==========================================
        report "--- STARTING CASE 1: IDEAL FRAME ---";
        send_frame(x"41", '0', '1');
        assert tb_done_latched = '1' and tb_err_latched = '0'
            report "CASE 1: expected rx_done_o, got none (or rx_err_o instead)" severity error;
        assert tb_data_latched = x"41"
            report "CASE 1: rx_data_o did not match the expected byte (0x41)" severity error;
        if tb_done_latched = '1' and tb_err_latched = '0' and tb_data_latched = x"41" then
            report "CASE 1: ideal frame verified correctly (0x41)";
        end if;

        -- ==========================================
        -- CASE 2: Glitch on the line (short noise)
        -- ==========================================
        report "--- STARTING CASE 2: GLITCH / NOISE ---";
        tb_rx_i <= '0';
        wait for 30 us; -- Shorter than the bit center's 52 us
        tb_rx_i <= '1';
        wait for 2 * BIT_PERIOD;
        assert tb_done_latched = '0' and tb_err_latched = '0'
            report "CASE 2: glitch should not be accepted as a frame (expected neither rx_done_o nor rx_err_o)" severity error;
        if tb_done_latched = '0' and tb_err_latched = '0' then
            report "CASE 2: glitch correctly rejected";
        end if;

        -- ==========================================
        -- CASE 3: Parity error
        -- Data: 01000001 (send parity '1' to force an error)
        -- ==========================================
        report "--- STARTING CASE 3: PARITY ERROR ---";
        send_frame(x"41", '1', '1');
        assert tb_err_latched = '1' and tb_done_latched = '0'
            report "CASE 3: expected rx_err_o for a parity error, not rx_done_o" severity error;
        if tb_err_latched = '1' and tb_done_latched = '0' then
            report "CASE 3: parity error correctly flagged";
        end if;

        -- ==========================================
        -- CASE 4: Framing error (no stop bit)
        -- ==========================================
        report "--- STARTING CASE 4: FRAMING ERROR ---";
        send_frame(x"41", '0', '0');
        assert tb_err_latched = '1' and tb_done_latched = '0'
            report "CASE 4: expected rx_err_o for a framing error, not rx_done_o" severity error;
        if tb_err_latched = '1' and tb_done_latched = '0' then
            report "CASE 4: framing error correctly flagged";
        end if;

        report "--- SIMULATION COMPLETE ---";
        wait;
    end process;

end tb;