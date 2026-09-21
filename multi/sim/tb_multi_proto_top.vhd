library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_multi_proto_top is
end tb_multi_proto_top;

architecture tb of tb_multi_proto_top is

    -- 1. DEVICE UNDER TEST COMPONENT
    component multi_proto_top is
        generic (
            clk_freq : integer := 100000000;
            baudrate : integer := 9600;
            scl_freq : integer := 100000
        );
        port (
            clk            : in  std_logic;
            reset_n        : in  std_logic;
            protocol_sel_i : in  std_logic_vector(1 downto 0);

            tx_out_o       : out std_logic;
            tx_oe_o        : out std_logic;
            rx_in_i        : in  std_logic;

            tx_start_i     : in  std_logic;
            tx_byte_i      : in  std_logic_vector(7 downto 0);
            tx_busy_o      : out std_logic;
            rx_data_o      : out std_logic_vector(7 downto 0);
            rx_done_o      : out std_logic;
            rx_err_o       : out std_logic;

            start_i        : in  std_logic;
            addr_i         : in  std_logic_vector(6 downto 0);
            rw_i           : in  std_logic;
            wdata_i        : in  std_logic_vector(7 downto 0);
            last_byte_i    : in  std_logic;
            rdata_o        : out std_logic_vector(7 downto 0);
            done_o         : out std_logic;
            busy_o         : out std_logic;
            ack_err_o      : out std_logic;

            scl_out_o      : out std_logic;
            scl_oe_o       : out std_logic;
            scl_in_i       : in  std_logic;
            sda_out_o      : out std_logic;
            sda_oe_o       : out std_logic;
            sda_in_i       : in  std_logic
        );
    end component;

    -- 2. TESTBENCH SIGNALS
    signal tb_clk       : std_logic := '0';
    signal tb_reset_n   : std_logic := '0';
    signal tb_proto_sel : std_logic_vector(1 downto 0) := "00";

    signal tb_tx_out : std_logic;
    signal tb_tx_oe  : std_logic;
    signal tb_rx_in  : std_logic := '1'; -- UART line idle at '1'

    signal tb_tx_start : std_logic := '0';
    signal tb_tx_byte  : std_logic_vector(7 downto 0) := (others => '0');
    signal tb_tx_busy  : std_logic;
    signal tb_rx_data  : std_logic_vector(7 downto 0);
    signal tb_rx_done  : std_logic;
    signal tb_rx_err   : std_logic;

    -- Latched outcome of the RX frame currently/last in flight -- rx_done_o
    -- and rx_err_o are single-cycle pulses; p_rx_result_latch below captures
    -- them into level signals p_stimulus can assert against after the fact.
    signal rx_done_latched : std_logic := '0';
    signal rx_err_latched  : std_logic := '0';
    signal rx_data_latched : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_i_prev       : std_logic := '1';

    signal tb_start     : std_logic := '0';
    signal tb_addr      : std_logic_vector(6 downto 0) := (others => '0');
    signal tb_rw        : std_logic := '0';
    signal tb_wdata     : std_logic_vector(7 downto 0) := (others => '0');
    signal tb_last_byte : std_logic := '0';
    signal tb_rdata     : std_logic_vector(7 downto 0);
    signal tb_done      : std_logic;
    signal tb_busy      : std_logic;
    signal tb_ack_err   : std_logic;

    signal tb_scl_out : std_logic;
    signal tb_scl_oe  : std_logic;
    signal tb_scl_in  : std_logic;
    signal tb_sda_out : std_logic;
    signal tb_sda_oe  : std_logic;
    signal tb_sda_in  : std_logic;

    -- Physical I2C bus (wired-AND) and the slave model's drivers
    signal scl_line : std_logic;
    signal sda_line : std_logic;
    signal sda_o_s  : std_logic := '1';
    signal sda_oe_s : std_logic := '0';
    signal bus_idle : std_logic := '1';

    constant CLK_PERIOD : time := 10 ns;       -- 100 MHz master clock
    constant BIT_PERIOD : time := 104.166 us;  -- UART bit period at 9600 baud

    constant UART_TEST_BYTE : std_logic_vector(7 downto 0) := x"41"; -- 'A'
    constant SLAVE_ADDR     : std_logic_vector(6 downto 0) := "1010000"; -- 0x50, responds

    type t_byte_array is array (natural range <>) of std_logic_vector(7 downto 0);

begin

    -- 3. MASTER CLOCK
    tb_clk <= not tb_clk after CLK_PERIOD / 2;

    -- 4. DUT
    dut : multi_proto_top
        generic map (
            clk_freq => 100000000,
            baudrate => 9600,
            scl_freq => 100000
        )
        port map (
            clk            => tb_clk,
            reset_n        => tb_reset_n,
            protocol_sel_i => tb_proto_sel,

            tx_out_o       => tb_tx_out,
            tx_oe_o        => tb_tx_oe,
            rx_in_i        => tb_rx_in,

            tx_start_i     => tb_tx_start,
            tx_byte_i      => tb_tx_byte,
            tx_busy_o      => tb_tx_busy,
            rx_data_o      => tb_rx_data,
            rx_done_o      => tb_rx_done,
            rx_err_o       => tb_rx_err,

            start_i        => tb_start,
            addr_i         => tb_addr,
            rw_i           => tb_rw,
            wdata_i        => tb_wdata,
            last_byte_i    => tb_last_byte,
            rdata_o        => tb_rdata,
            done_o         => tb_done,
            busy_o         => tb_busy,
            ack_err_o      => tb_ack_err,

            scl_out_o      => tb_scl_out,
            scl_oe_o       => tb_scl_oe,
            scl_in_i       => tb_scl_in,
            sda_out_o      => tb_sda_out,
            sda_oe_o       => tb_sda_oe,
            sda_in_i       => tb_sda_in
        );

    -- 5. PHYSICAL I2C BUS: open-drain model with pull-up (wired-AND), same
    -- pattern as tb_i2c_master.vhd since the DUT here exposes split logical
    -- ports (out/oe/in) instead of a single inout.
    scl_line <= '0' when (tb_scl_oe = '1' and tb_scl_out = '0') else '1';
    sda_line <= '0' when (tb_sda_oe = '1' and tb_sda_out = '0') or
                          (sda_oe_s = '1' and sda_o_s = '0') else '1';
    tb_scl_in <= scl_line;
    tb_sda_in <= sda_line;

    -- 6. BUS MONITOR: detects START/STOP and keeps bus_idle up to date
    p_bus_monitor : process
    begin
        loop
            wait until sda_line'event and sda_line = '0' and scl_line = '1';
            bus_idle <= '0';
            report "BUS: START condition detected";

            wait until sda_line'event and sda_line = '1' and scl_line = '1';
            bus_idle <= '1';
            report "BUS: STOP condition detected";
        end loop;
    end process p_bus_monitor;

    -- 7. I2C SLAVE MODEL (same as tb_i2c_master.vhd / tb_i2c_top.vhd)
    p_slave_model : process
        procedure wait_bit_or_stop(
            variable bit_val   : out std_logic;
            variable stop_seen : out boolean
        ) is
        begin
            wait until rising_edge(scl_line);
            bit_val := sda_line;
            wait until falling_edge(scl_line) or (sda_line'event and scl_line = '1');
            stop_seen := (scl_line = '1');
        end procedure;

        variable v_bit    : std_logic;
        variable v_stop   : boolean;
        variable v_byte   : std_logic_vector(7 downto 0);
        variable v_addr   : std_logic_vector(6 downto 0);
        variable v_rw     : std_logic;
        variable v_ack    : std_logic;
        variable v_rd_val : unsigned(7 downto 0) := x"A5";
    begin
        sda_oe_s <= '0';
        sda_o_s  <= '1';

        main_loop : loop
            wait until sda_line'event and sda_line = '0' and scl_line = '1';
            report "SLAVE: START received";

            for i in 7 downto 0 loop
                wait until rising_edge(scl_line);
                v_byte(i) := sda_line;
            end loop;
            v_addr := v_byte(7 downto 1);
            v_rw   := v_byte(0);

            wait until falling_edge(scl_line);
            if v_addr = SLAVE_ADDR then
                report "SLAVE: address recognized, ACK";
                sda_oe_s <= '1';
                sda_o_s  <= '0';
            else
                report "SLAVE: address not recognized, NACK";
                sda_oe_s <= '0';
            end if;
            wait until rising_edge(scl_line);
            wait until falling_edge(scl_line);
            sda_oe_s <= '0';

            if v_addr = SLAVE_ADDR then
                if v_rw = '0' then
                    byte_loop_w : loop
                        v_stop := false;
                        for i in 7 downto 0 loop
                            wait_bit_or_stop(v_bit, v_stop);
                            exit when v_stop;
                            v_byte(i) := v_bit;
                        end loop;
                        exit byte_loop_w when v_stop;

                        report "SLAVE: write byte received";
                        sda_oe_s <= '1';
                        sda_o_s  <= '0'; -- ACK the data
                        wait until rising_edge(scl_line);
                        wait until falling_edge(scl_line);
                        sda_oe_s <= '0';
                    end loop byte_loop_w;
                else
                    byte_loop_r : loop
                        v_byte := std_logic_vector(v_rd_val);
                        for i in 7 downto 0 loop
                            -- SCL is already low for this bit's window (left
                            -- that way by the previous falling edge: the
                            -- address ack's on the first pass, or the
                            -- previous byte's ack/nack on later ones), so the
                            -- bit can be placed right away without consuming
                            -- another edge
                            sda_oe_s <= '1';
                            sda_o_s  <= v_byte(i);
                            wait until rising_edge(scl_line);
                            if i /= 0 then
                                wait until falling_edge(scl_line);
                            end if;
                        end loop;
                        report "SLAVE: read byte sent";
                        v_rd_val := v_rd_val + 1;

                        wait until falling_edge(scl_line);
                        sda_oe_s <= '0';
                        wait until rising_edge(scl_line);
                        v_ack := sda_line;
                        wait until falling_edge(scl_line);
                        exit byte_loop_r when v_ack = '1';
                    end loop byte_loop_r;
                end if;
            end if;

            if bus_idle /= '1' then
                wait until bus_idle = '1';
            end if;
            report "SLAVE: transaction finished, bus free";
        end loop main_loop;
    end process p_slave_model;

    -- 8. UART TX CAPTURE AND VERIFICATION (same technique as tb_uart_top.vhd)
    -- Listens on tx_out_o, reconstructs the host-driven transmitted byte
    -- (LSB first) and compares it against UART_TEST_BYTE -- a byte-by-byte
    -- check, not just waveform inspection.
    p_tx_capture : process
        variable v_byte    : std_logic_vector(7 downto 0);
        variable v_par_tx  : std_logic;
        variable v_par_calc : std_logic;
        variable v_stop    : std_logic;
    begin
        wait until falling_edge(tb_tx_out); -- start of the start bit

        wait for BIT_PERIOD * 1.5; -- center of bit 0 (LSB)
        for i in 0 to 7 loop
            v_byte(i) := tb_tx_out;
            wait for BIT_PERIOD;
        end loop;
        v_par_tx := tb_tx_out; -- center of the parity bit
        wait for BIT_PERIOD;
        v_stop := tb_tx_out; -- center of the stop bit

        v_par_calc := v_byte(0) xor v_byte(1) xor v_byte(2) xor v_byte(3) xor
                      v_byte(4) xor v_byte(5) xor v_byte(6) xor v_byte(7);

        assert v_byte = UART_TEST_BYTE
            report "UART: incorrect transmitted byte" severity error;
        assert v_par_tx = v_par_calc
            report "UART: incorrect transmitted parity" severity error;
        assert v_stop = '1'
            report "UART: incorrect stop bit (framing error)" severity error;
        assert tb_tx_oe = '1'
            report "UART: tx_oe_o should be active while transmitting" severity error;

        if v_byte = UART_TEST_BYTE and v_par_tx = v_par_calc and v_stop = '1' and tb_tx_oe = '1' then
            report "UART: host-driven frame verified correctly (byte=0x41)";
        end if;
        wait; -- a single frame in this testbench
    end process p_tx_capture;

    -- 8b. UART RX RESULT LATCH (same technique as tb_uart_top.vhd/tb_uart_rx.vhd)
    -- rx_done_o/rx_err_o are single-cycle pulses; latches them into level
    -- signals p_stimulus can assert against after the fact.
    p_rx_result_latch : process(tb_clk)
    begin
        if rising_edge(tb_clk) then
            if rx_i_prev = '1' and tb_rx_in = '0' then
                rx_done_latched <= '0';
                rx_err_latched  <= '0';
            elsif tb_rx_done = '1' then
                rx_done_latched <= '1';
                rx_data_latched <= tb_rx_data;
            elsif tb_rx_err = '1' then
                rx_err_latched <= '1';
            end if;
            rx_i_prev <= tb_rx_in;
        end if;
    end process p_rx_result_latch;

    -- 9. STIMULUS CHOREOGRAPHY
    p_stimulus : process
        procedure host_write(
            constant addr  : in std_logic_vector(6 downto 0);
            constant bytes : in t_byte_array
        ) is
            variable n : integer := bytes'length;
        begin
            tb_addr  <= addr;
            tb_rw    <= '0';
            tb_wdata <= bytes(0);
            if n = 1 then
                tb_last_byte <= '1';
            else
                tb_last_byte <= '0';
            end if;
            tb_start <= '1';
            wait until rising_edge(tb_clk);
            tb_start <= '0';

            if n > 1 then
                tb_wdata <= bytes(1);
                if n = 2 then
                    tb_last_byte <= '1';
                else
                    tb_last_byte <= '0';
                end if;
            end if;

            for k in 0 to n - 1 loop
                wait until tb_done = '1' or tb_busy = '0';
                exit when tb_busy = '0';
                if k + 2 <= n - 1 then
                    tb_wdata <= bytes(k + 2);
                    if (k + 2) = n - 1 then
                        tb_last_byte <= '1';
                    else
                        tb_last_byte <= '0';
                    end if;
                end if;
            end loop;

            if tb_busy /= '0' then
                wait until tb_busy = '0';
            end if;
        end procedure;

        procedure host_read(
            constant addr    : in  std_logic_vector(6 downto 0);
            constant n_bytes : in  integer;
            variable results : out t_byte_array
        ) is
        begin
            tb_addr <= addr;
            tb_rw   <= '1';
            if n_bytes = 1 then
                tb_last_byte <= '1';
            else
                tb_last_byte <= '0';
            end if;
            tb_start <= '1';
            wait until rising_edge(tb_clk);
            tb_start <= '0';

            if n_bytes > 1 then
                if n_bytes = 2 then
                    tb_last_byte <= '1';
                else
                    tb_last_byte <= '0';
                end if;
            end if;

            for k in 0 to n_bytes - 1 loop
                wait until tb_done = '1' or tb_busy = '0';
                exit when tb_busy = '0';
                results(k) := tb_rdata;
                if k + 2 <= n_bytes - 1 then
                    if (k + 2) = n_bytes - 1 then
                        tb_last_byte <= '1';
                    else
                        tb_last_byte <= '0';
                    end if;
                end if;
            end loop;

            if tb_busy /= '0' then
                wait until tb_busy = '0';
            end if;
        end procedure;

        variable v_read1 : t_byte_array(0 to 0);

    begin
        -- ================================================================
        -- PHASE 1: UART (protocol_sel_i = "00")
        -- ================================================================
        report "--- PHASE 1: UART (protocol_sel_i = 00) ---";
        tb_reset_n   <= '0';
        tb_proto_sel <= "00";
        tb_rx_in     <= '1';
        wait for 100 ns;
        tb_reset_n <= '1';
        wait for 10 * CLK_PERIOD;

        -- CASE 1: host drives TX directly (tx_start_i/tx_byte_i), with no
        -- RX activity involved -- p_tx_capture verifies the frame on tx_out_o.
        report "--- UART CASE 1: HOST-DRIVEN TX (0x41) ---";
        tb_tx_byte  <= UART_TEST_BYTE;
        tb_tx_start <= '1';
        wait until rising_edge(tb_clk);
        tb_tx_start <= '0';
        wait until tb_tx_busy = '0'; -- wait for the frame to finish transmitting

        -- CASE 2: host observes RX directly (rx_data_o/rx_done_o), with no
        -- TX activity involved. Frame 0x41 ('A'): start + 8 data bits
        -- LSB-first + even parity + stop.
        report "--- UART CASE 2: HOST-OBSERVED RX (0x41) ---";
        tb_rx_in <= '0'; wait for BIT_PERIOD; -- start
        tb_rx_in <= '1'; wait for BIT_PERIOD; -- bit0 (LSB)
        tb_rx_in <= '0'; wait for BIT_PERIOD; -- bit1
        tb_rx_in <= '0'; wait for BIT_PERIOD; -- bit2
        tb_rx_in <= '0'; wait for BIT_PERIOD; -- bit3
        tb_rx_in <= '0'; wait for BIT_PERIOD; -- bit4
        tb_rx_in <= '0'; wait for BIT_PERIOD; -- bit5
        tb_rx_in <= '1'; wait for BIT_PERIOD; -- bit6
        tb_rx_in <= '0'; wait for BIT_PERIOD; -- bit7 (MSB)
        tb_rx_in <= '0'; wait for BIT_PERIOD; -- parity (even, two '1's -> '0')
        tb_rx_in <= '1'; wait for BIT_PERIOD; -- stop
        wait for 2 * BIT_PERIOD;

        assert rx_done_latched = '1' and rx_err_latched = '0'
            report "UART CASE 2: expected rx_done_o, got none (or rx_err_o instead)" severity error;
        assert rx_data_latched = UART_TEST_BYTE
            report "UART CASE 2: rx_data_o did not match the expected byte (0x41)" severity error;
        if rx_done_latched = '1' and rx_err_latched = '0' and rx_data_latched = UART_TEST_BYTE then
            report "UART CASE 2: host-observed frame verified correctly (0x41)";
        end if;

        -- ================================================================
        -- PHASE 2: reset and switch to I2C (protocol_sel_i = "01")
        -- ================================================================
        report "--- PHASE 2: reset and switch to I2C (protocol_sel_i = 01) ---";
        tb_reset_n   <= '0';
        tb_proto_sel <= "01";
        tb_rx_in     <= '1';
        wait for 10 * CLK_PERIOD;
        wait until falling_edge(tb_clk);
        tb_reset_n <= '1';
        wait for 20 * CLK_PERIOD;

        report "--- I2C CASE 1: 1-BYTE WRITE ---";
        host_write(SLAVE_ADDR, t_byte_array'(0 => x"3C"));
        assert tb_ack_err = '0'
            report "I2C: expected ACK but got NACK (write)" severity error;
        wait for 5 us;

        report "--- I2C CASE 2: 1-BYTE READ ---";
        host_read(SLAVE_ADDR, 1, v_read1);
        assert v_read1(0) = x"A5"
            report "I2C: byte read does not match the expected value (0xA5)" severity error;
        if v_read1(0) = x"A5" then
            report "I2C: byte read verified correctly (0xA5)";
        end if;
        wait for 5 us;

        -- ================================================================
        -- PHASE 3: switch to protocol_sel_i = "11" (reserved) long after
        -- I2C has cleanly finished, with NO intervening reset. Both engines
        -- are already idle (busy_o has been '0' since the end of I2C CASE
        -- 2), so this switch doesn't interrupt any transaction in flight --
        -- unlike forcing a reserved code mid-frame (see multi_proto_report.md,
        -- limitations section).
        -- ================================================================
        report "--- PHASE 3: switch to protocol_sel_i = 11 (reserved), no reset, with I2C already idle ---";
        assert tb_busy = '0'
            report "PHASE 3: I2C should be idle (busy_o='0') before this switch" severity error;
        tb_proto_sel <= "11";

        -- Let enough time pass to cover several tick periods of both
        -- protocols (UART ~6.51us, I2C ~2.5us with the default generics)
        -- and confirm neither one pulses or drives its bus again just
        -- because the selector changed.
        wait for 40 us;

        assert tb_tx_oe = '0'
            report "PHASE 3: tx_oe_o should be '0' with protocol_sel_i=11" severity error;
        assert tb_sda_oe = '0'
            report "PHASE 3: sda_oe_o should be '0' with protocol_sel_i=11" severity error;
        assert tb_scl_oe = '0'
            report "PHASE 3: scl_oe_o should be '0' with protocol_sel_i=11" severity error;
        assert tb_busy = '0'
            report "PHASE 3: busy_o should not reassert just because protocol_sel_i changed" severity error;

        if tb_tx_oe = '0' and tb_sda_oe = '0' and tb_scl_oe = '0' and tb_busy = '0' then
            report "PHASE 3: protocol_sel_i=11 verified as inert (both engines were already idle)";
        end if;

        report "--- SIMULATION COMPLETE ---";
        wait;
    end process p_stimulus;

end tb;
