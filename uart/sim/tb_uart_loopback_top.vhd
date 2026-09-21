library ieee;
use ieee.std_logic_1164.all;

entity tb_uart_loopback_top is
end tb_uart_loopback_top;

architecture bhv of tb_uart_loopback_top is

    -- 1. DEVICE-UNDER-TEST (DUT) COMPONENT DECLARATION
    component uart_loopback_top is
        port (
            clk      : in  std_logic;
            reset_n  : in  std_logic;
            rx_pin_i : in  std_logic;
            tx_pin_o : out std_logic
        );
    end component;

    -- 2. TESTBENCH SIGNALS
    signal clk       : std_logic := '0';
    signal reset_n   : std_logic := '0';
    signal rx_pin_i  : std_logic := '1'; -- Line idle at '1'
    signal tx_pin_o  : std_logic;

    -- 3. TIME CONSTANTS
    constant CLK_PERIOD : time := 10 ns;        -- 100 MHz master clock
    constant BIT_PERIOD : time := 104.166 us;   -- Bit period at 9600 baud

    constant UART_TEST_BYTE : std_logic_vector(7 downto 0) := x"41"; -- 'A'

begin

    -- 4. TOP-LEVEL INSTANTIATION
    dut : uart_loopback_top
        port map (
            clk      => clk,
            reset_n  => reset_n,
            rx_pin_i => rx_pin_i,
            tx_pin_o => tx_pin_o
        );

    -- 5. MASTER CLOCK GENERATION
    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- 5b. ECHO CAPTURE AND VERIFICATION
    -- Listens on tx_pin_o, reconstructs the echoed byte (LSB first) and
    -- compares it against UART_TEST_BYTE -- a byte-by-byte check, not just
    -- waveform inspection.
    p_echo_capture : process
        variable v_byte     : std_logic_vector(7 downto 0);
        variable v_par_rx   : std_logic;
        variable v_par_calc : std_logic;
        variable v_stop     : std_logic;
    begin
        wait until falling_edge(tx_pin_o); -- start of the echo's start bit

        wait for BIT_PERIOD * 1.5; -- center of bit 0 (LSB)
        for i in 0 to 7 loop
            v_byte(i) := tx_pin_o;
            wait for BIT_PERIOD;
        end loop;
        v_par_rx := tx_pin_o; -- center of the parity bit
        wait for BIT_PERIOD;
        v_stop := tx_pin_o; -- center of the stop bit

        v_par_calc := v_byte(0) xor v_byte(1) xor v_byte(2) xor v_byte(3) xor
                      v_byte(4) xor v_byte(5) xor v_byte(6) xor v_byte(7);

        assert v_byte = UART_TEST_BYTE
            report "Echo: incorrect byte" severity error;
        assert v_par_rx = v_par_calc
            report "Echo: incorrect parity" severity error;
        assert v_stop = '1'
            report "Echo: incorrect stop bit (framing error)" severity error;

        if v_byte = UART_TEST_BYTE and v_par_rx = v_par_calc and v_stop = '1' then
            report "Echo verified correctly (byte=0x41)";
        end if;
        wait; -- a single frame in this testbench
    end process p_echo_capture;

    -- 6. STIMULUS PROCESS
    stim_process : process
    begin
        -- Initial state and reset
        reset_n  <= '0';
        rx_pin_i <= '1';
        wait for 100 ns;
        reset_n  <= '1';
        wait for 10 * CLK_PERIOD;

        -- ============================================================
        -- FRAME INJECTION: send byte 0x41 (letter 'A')
        -- Configuration: 8 data bits, LSB first, even parity, 1 stop bit
        -- ============================================================

        -- [1] START bit
        rx_pin_i <= '0';
        wait for BIT_PERIOD;

        -- [2] 8 DATA bits (0x41 -> Binary: 01000001)
        rx_pin_i <= '1'; -- Bit 0 (LSB)
        wait for BIT_PERIOD;
        rx_pin_i <= '0'; -- Bit 1
        wait for BIT_PERIOD;
        rx_pin_i <= '0'; -- Bit 2
        wait for BIT_PERIOD;
        rx_pin_i <= '0'; -- Bit 3
        wait for BIT_PERIOD;
        rx_pin_i <= '0'; -- Bit 4
        wait for BIT_PERIOD;
        rx_pin_i <= '0'; -- Bit 5
        wait for BIT_PERIOD;
        rx_pin_i <= '1'; -- Bit 6
        wait for BIT_PERIOD;
        rx_pin_i <= '0'; -- Bit 7 (MSB)
        wait for BIT_PERIOD;

        -- [3] PARITY bit
        -- The data has two '1's, so the computed even parity is '0'
        rx_pin_i <= '0';
        wait for BIT_PERIOD;

        -- [4] STOP bit
        rx_pin_i <= '1';
        wait for BIT_PERIOD;

        -- ============================================================
        -- WAIT FOR THE ECHO
        -- Give the receiver enough time to finish, trigger the internal
        -- TX, and have it send the data back out on tx_pin_o.
        -- ============================================================
        wait for 2 ms;

        report "Simulation completed successfully." severity note;
        wait;
    end process;

end bhv;
