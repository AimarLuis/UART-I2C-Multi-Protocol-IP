library ieee;
use ieee.std_logic_1164.all;

entity tb_uart_tx is
end tb_uart_tx;

architecture tb of tb_uart_tx is

    -- 1. COMPONENT DECLARATIONS
    component cnt is
        port (
            clk       : in std_logic;
            reset_n   : in std_logic;
            tick_16_o : out std_logic
        );
    end component;

    component uart_tx is
        port (
        clk           : in  std_logic;
        reset_n       : in  std_logic;
        tx_start_i    : in  std_logic;
        tx_byte_i     : in  std_logic_vector(7 downto 0);
        tick_16_i     : in  std_logic; -- Clean tick from the counter

        tx_o          : out std_logic;
        tx_busy_o     : out std_logic
        );
    end component;

    -- 2. TESTBENCH INTERNAL SIGNALS (the wiring)
    signal tb_clk       : std_logic := '0';
    signal tb_reset_n   : std_logic := '0';
    signal tb_tx_byte   : std_logic_vector(7 downto 0) := (others => '0');
    signal tb_start     : std_logic := '0';
    signal tb_tick_16   : std_logic;
    signal tb_tx        : std_logic;

    -- Simulation constants for 100 MHz
    constant CLK_PERIOD : time := 10 ns;
    constant BIT_PERIOD : time := 104.166 us; -- Bit period at 9600 baud

    constant TX_TEST_BYTE : std_logic_vector(7 downto 0) := x"41"; -- 'A'

begin

    -- 3. MASTER CLOCK GENERATION (100 MHz)
    tb_clk <= not tb_clk after CLK_PERIOD/2;

    -- 4. BAUD RATE GENERATOR INSTANTIATION (DUT 1)
    u_baud_gen : cnt
        generic map (
            clk_freq => 100000000,
            baudrate => 9600
        )
        port map (
            clk       => tb_clk,
            reset_n   => tb_reset_n,
            tick_16_o => tb_tick_16 -- Drive the pulse onto the internal wire
        );

    -- 5. TRANSMITTER INSTANTIATION (DUT 2)
    -- No generic map here: unlike cnt, uart_tx declares no generics.
    u_tx : uart_tx
        port map (
            clk           => tb_clk,
            reset_n        => tb_reset_n,
            tx_start_i    => tb_start,     -- Connected to the TB's own signal
            tx_byte_i     => tb_tx_byte,   -- Connected to the TB's own signal
            tick_16_i     => tb_tick_16,   -- Receives the pulse from the counter
            tx_o          => tb_tx,        -- Physical serial output
            tx_busy_o     => open          -- Left open (dangling) for now
        );

    -- 6a. TRANSMITTED-FRAME CAPTURE AND VERIFICATION
    -- Listens on tb_tx, reconstructs the transmitted byte (LSB first) and
    -- compares it against TX_TEST_BYTE -- a byte-by-byte check, not just
    -- timing/waveform inspection.
    p_tx_capture : process
        variable v_byte     : std_logic_vector(7 downto 0);
        variable v_par_tx   : std_logic;
        variable v_par_calc : std_logic;
        variable v_stop     : std_logic;
    begin
        wait until falling_edge(tb_tx); -- start of the start bit

        wait for BIT_PERIOD * 1.5; -- center of bit 0 (LSB)
        for i in 0 to 7 loop
            v_byte(i) := tb_tx;
            wait for BIT_PERIOD;
        end loop;
        v_par_tx := tb_tx; -- center of the parity bit
        wait for BIT_PERIOD;
        v_stop := tb_tx; -- center of the stop bit

        v_par_calc := v_byte(0) xor v_byte(1) xor v_byte(2) xor v_byte(3) xor
                      v_byte(4) xor v_byte(5) xor v_byte(6) xor v_byte(7);

        assert v_byte = TX_TEST_BYTE
            report "TX: incorrect transmitted byte" severity error;
        assert v_par_tx = v_par_calc
            report "TX: incorrect transmitted parity" severity error;
        assert v_stop = '1'
            report "TX: incorrect stop bit" severity error;

        if v_byte = TX_TEST_BYTE and v_par_tx = v_par_calc and v_stop = '1' then
            report "TX: frame verified correctly (byte=0x41)";
        end if;
        wait; -- a single frame in this testbench
    end process p_tx_capture;

    -- 6b. STIMULUS PROCESS (the signal choreography)
    p_stimulus : process
    begin
        -- Initial state with reset asserted
        tb_reset_n <= '0';
        tb_start   <= '0';
        tb_tx_byte <= x"00";
        wait for 10 * CLK_PERIOD;

        -- Release reset
        tb_reset_n <= '1';
        wait for 10 * CLK_PERIOD;

        -- Prepare the data: transmit the letter 'A' -> Hex 41 -> Binary 01000001
        tb_tx_byte <= TX_TEST_BYTE;

        -- Assert the 'start' pulse for a single clock cycle
        tb_start   <= '1';
        wait for CLK_PERIOD;
        tb_start   <= '0';

        -- One bit at 9600 baud takes ~104 us.
        -- Since we transmit: Start(1) + Data(8) + Parity(1) + Stop(1) = 11 bits total.
        -- 11 bits * 104 us = 1.14 ms total transmission time.
        -- Wait 1.5 ms so the whole frame is visible.
        wait for 1.5 ms;

        -- Stop the simulation
        wait;
    end process;

end tb;