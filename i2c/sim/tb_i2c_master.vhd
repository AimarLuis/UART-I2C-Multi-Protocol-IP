library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_i2c_master is
end tb_i2c_master;

architecture tb of tb_i2c_master is

    -- 1. COMPONENTS
    component i2c_clk_div is
        generic (
            clk_freq : integer := 100000000;
            scl_freq : integer := 100000
        );
        port (
            clk      : in  std_logic;
            reset_n  : in  std_logic;
            tick_4_o : out std_logic
        );
    end component;

    component i2c_master is
        port (
            clk           : in  std_logic;
            reset_n       : in  std_logic;

            start_i       : in  std_logic;
            addr_i        : in  std_logic_vector(6 downto 0);
            rw_i          : in  std_logic;
            wdata_i       : in  std_logic_vector(7 downto 0);
            last_byte_i   : in  std_logic;
            rdata_o       : out std_logic_vector(7 downto 0);
            done_o        : out std_logic;
            busy_o        : out std_logic;
            ack_err_o     : out std_logic;

            tick_4_i      : in  std_logic;

            sda_i         : in  std_logic;
            sda_o         : out std_logic;
            sda_oe_o      : out std_logic;
            scl_i         : in  std_logic;
            scl_o         : out std_logic;
            scl_oe_o      : out std_logic
        );
    end component;

    -- 2. INTERNAL SIGNALS
    signal tb_clk       : std_logic := '0';
    signal tb_reset_n   : std_logic := '0';
    signal tb_tick_4    : std_logic;

    -- Master control interface (host side)
    signal tb_start     : std_logic := '0';
    signal tb_addr      : std_logic_vector(6 downto 0) := (others => '0');
    signal tb_rw        : std_logic := '0';
    signal tb_wdata     : std_logic_vector(7 downto 0) := (others => '0');
    signal tb_last_byte : std_logic := '0';
    signal tb_rdata     : std_logic_vector(7 downto 0);
    signal tb_done      : std_logic;
    signal tb_busy      : std_logic;
    signal tb_ack_err   : std_logic;

    -- Physical I2C bus (resolved line) and each side's open-drain drivers
    signal sda_line      : std_logic;
    signal scl_line       : std_logic;

    signal sda_o_m, sda_oe_m : std_logic;
    signal scl_o_m, scl_oe_m : std_logic;

    signal sda_o_s : std_logic := '1';
    signal sda_oe_s : std_logic := '0';

    -- Indicates the bus is idle (after a STOP condition)
    signal bus_idle : std_logic := '1';

    constant CLK_PERIOD  : time := 10 ns; -- 100 MHz
    constant SLAVE_ADDR  : std_logic_vector(6 downto 0) := "1010000"; -- 0x50, responds
    constant BAD_ADDR    : std_logic_vector(6 downto 0) := "1111111"; -- nobody responds

    type t_byte_array is array (natural range <>) of std_logic_vector(7 downto 0);

begin

    -- 3. MASTER CLOCK
    tb_clk <= not tb_clk after CLK_PERIOD/2;

    -- 4. SCL PHASE GENERATOR (DUT 1)
    u_scl_gen : i2c_clk_div
        generic map (
            clk_freq => 100000000,
            scl_freq => 100000
        )
        port map (
            clk      => tb_clk,
            reset_n  => tb_reset_n,
            tick_4_o => tb_tick_4
        );

    -- 5. I2C MASTER (DUT 2)
    u_i2c : i2c_master
        port map (
            clk         => tb_clk,
            reset_n     => tb_reset_n,

            start_i     => tb_start,
            addr_i      => tb_addr,
            rw_i        => tb_rw,
            wdata_i     => tb_wdata,
            last_byte_i => tb_last_byte,
            rdata_o     => tb_rdata,
            done_o      => tb_done,
            busy_o      => tb_busy,
            ack_err_o   => tb_ack_err,

            tick_4_i    => tb_tick_4,

            sda_i       => sda_line,
            sda_o       => sda_o_m,
            sda_oe_o    => sda_oe_m,
            scl_i       => scl_line,
            scl_o       => scl_o_m,
            scl_oe_o    => scl_oe_m
        );

    -- 6. PHYSICAL BUS: open-drain model with pull-up (wired-AND)
    -- Only the master drives SCL in this testbench (no slave clock stretching)
    scl_line <= '0' when (scl_oe_m = '1' and scl_o_m = '0') else '1';
    sda_line <= '0' when (sda_oe_m = '1' and sda_o_m = '0') or
                          (sda_oe_s = '1' and sda_o_s = '0') else '1';

    -- 7. BUS MONITOR: detects START/STOP and keeps bus_idle up to date
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

    -- 8. I2C SLAVE MODEL
    p_slave_model : process
        -- Waits for the next SCL rising edge and captures the SDA bit.
        -- If a STOP condition appears instead of a normal bit (SDA rises
        -- while SCL is high), it's flagged via stop_seen instead of
        -- returning a bit.
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
            -- Wait for a START condition
            wait until sda_line'event and sda_line = '0' and scl_line = '1';
            report "SLAVE: START received";

            -- Receive the address + R/W byte (MSB first)
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
                    -- Write: keep receiving bytes until the master stops
                    byte_loop_w : loop
                        v_stop := false;
                        for i in 7 downto 0 loop
                            wait_bit_or_stop(v_bit, v_stop);
                            exit when v_stop;
                            v_byte(i) := v_bit;
                        end loop;
                        exit byte_loop_w when v_stop;

                        report "SLAVE: write byte received";
                        -- wait_bit_or_stop already consumed the falling edge
                        -- that opens the ack window (SCL is already low here)
                        sda_oe_s <= '1';
                        sda_o_s  <= '0'; -- ACK the data
                        wait until rising_edge(scl_line);
                        wait until falling_edge(scl_line);
                        sda_oe_s <= '0';
                    end loop byte_loop_w;
                else
                    -- Read: send bytes until the master responds with a NACK
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
                        sda_oe_s <= '0'; -- release SDA so the master can ack/nack
                        wait until rising_edge(scl_line);
                        v_ack := sda_line;
                        wait until falling_edge(scl_line);
                        exit byte_loop_r when v_ack = '1'; -- master NACK: last byte
                    end loop byte_loop_r;
                end if;
            end if;

            -- Wait for a STOP condition (if not already detected)
            if bus_idle /= '1' then
                wait until bus_idle = '1';
            end if;
            report "SLAVE: transaction finished, bus free";
        end loop main_loop;
    end process p_slave_model;

    -- 9. STIMULUS CHOREOGRAPHY (Test Cases)
    p_stimulus : process
        -- Launches an N-byte write and waits for it to finish.
        -- wdata_i/last_byte_i are pre-loaded "one byte ahead", exactly as
        -- i2c_master's internal protocol requires (see the comment in
        -- i2c_master.vhd: "sampled at start_i and at each done_o").
        procedure host_write(
            constant addr  : in std_logic_vector(6 downto 0);
            constant bytes : in t_byte_array
        ) is
            variable n : integer := bytes'length;
        begin
            tb_addr      <= addr;
            tb_rw        <= '0';
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
                -- if the address gets a NACK the master aborts straight to
                -- stop_cond without ever pulsing done_o, so we also need to
                -- exit when busy_o drops without having seen done_o
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

            -- "wait until" only fires on an edge: if busy_o already dropped
            -- to '0' (aborted on an address NACK) there's no need to wait again
            if tb_busy /= '0' then
                wait until tb_busy = '0';
            end if;
        end procedure;

        -- Launches an N-byte read and returns the bytes read.
        procedure host_read(
            constant addr    : in  std_logic_vector(6 downto 0);
            constant n_bytes : in  integer;
            variable results : out t_byte_array
        ) is
        begin
            tb_addr      <= addr;
            tb_rw <= '1';
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

            -- "wait until" only fires on an edge: if busy_o already dropped
            -- to '0' (aborted on an address NACK) there's no need to wait again
            if tb_busy /= '0' then
                wait until tb_busy = '0';
            end if;
        end procedure;

        variable v_read1 : t_byte_array(0 to 0);
        variable v_read2 : t_byte_array(0 to 1);

    begin
        -- INITIAL RESET
        tb_reset_n <= '0';
        tb_start   <= '0';
        wait for 10 * CLK_PERIOD;
        wait until falling_edge(tb_clk);
        tb_reset_n <= '1';
        wait for 20 * CLK_PERIOD;

        -- ==========================================
        -- CASE 1: 1-byte write, slave responds
        -- ==========================================
        report "--- STARTING CASE 1: 1-BYTE WRITE ---";
        host_write(SLAVE_ADDR, t_byte_array'(0 => x"3C"));
        assert tb_ack_err = '0'
            report "CASE 1: expected ACK but got NACK" severity error;
        wait for 5 us;

        -- ==========================================
        -- CASE 2: 2-byte write (tests chaining)
        -- ==========================================
        report "--- STARTING CASE 2: 2-BYTE WRITE ---";
        host_write(SLAVE_ADDR, t_byte_array'(x"AA", x"55"));
        assert tb_ack_err = '0'
            report "CASE 2: expected ACK but got NACK" severity error;
        wait for 5 us;

        -- ==========================================
        -- CASE 3: 1-byte read
        -- ==========================================
        report "--- STARTING CASE 3: 1-BYTE READ ---";
        host_read(SLAVE_ADDR, 1, v_read1);
        -- The slave model's v_rd_val starts at x"A5" and this is the first
        -- read of the simulation, so the first byte it ever sends is x"A5".
        assert v_read1(0) = x"A5"
            report "CASE 3: byte read does not match the expected value (0xA5)" severity error;
        if v_read1(0) = x"A5" then
            report "CASE 3: byte read verified correctly (0xA5)";
        end if;
        wait for 5 us;

        -- ==========================================
        -- CASE 4: 2-byte read
        -- ==========================================
        report "--- STARTING CASE 4: 2-BYTE READ ---";
        host_read(SLAVE_ADDR, 2, v_read2);
        -- v_rd_val carries over from CASE 3 (it incremented to x"A6" after
        -- sending that byte), so this read gets x"A6" then x"A7".
        assert v_read2(0) = x"A6" and v_read2(1) = x"A7"
            report "CASE 4: bytes read do not match the expected sequence (0xA6, 0xA7)" severity error;
        if v_read2(0) = x"A6" and v_read2(1) = x"A7" then
            report "CASE 4: bytes read verified correctly (0xA6, 0xA7)";
        end if;
        wait for 5 us;

        -- ==========================================
        -- CASE 5: unanswered address -> address NACK
        -- ==========================================
        report "--- STARTING CASE 5: ADDRESS NACK ---";
        host_write(BAD_ADDR, t_byte_array'(0 => x"00"));
        assert tb_ack_err = '1'
            report "CASE 5: expected NACK but got ACK" severity error;
        wait for 5 us;

        report "--- SIMULATION COMPLETE ---";
        wait;
    end process p_stimulus;

end tb;
