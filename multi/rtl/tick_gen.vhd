library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Shared free-running tick generator for multi_proto_top.
--
-- Structurally the same counter as cnt.vhd (UART) and i2c_clk_div.vhd (I2C):
-- it counts up to a threshold and emits a single-cycle pulse. The two
-- protocols need different thresholds (16x oversampling for UART vs. 4
-- phases per SCL period for I2C), so both are precomputed as constants,
-- exactly the way each original module already derives its own, and a
-- 2-to-1 mux picks the active one at runtime from protocol_sel_i.
--
-- The resulting pulse is then gated onto exactly one of the two outputs
-- (or neither, for the reserved/idle codes), so the inactive protocol
-- engine never sees a tick and stays parked.
--
-- It also generates engines_reset_n_o: a one-cycle-wide active-low pulse
-- every time protocol_sel_i changes value, on top of whatever the external
-- reset_n is doing. multi_proto_top feeds this (instead of the raw
-- reset_n) into uart_rx/uart_tx/i2c_master's own reset_n input, so a
-- protocol switch can never resume one of them from whatever state it was
-- parked in -- it always re-enters from idle. Without this, a stray
-- start_i/rx_in_i toggle received while an engine isn't selected would park
-- it mid-FSM (not in idle), and switching back to it later would silently
-- resume that stale state instead of starting fresh.
entity tick_gen is
    generic (
        clk_freq : integer := 100000000;
        baudrate : integer := 9600;    -- UART: tick_max = clk_freq / (16 * baudrate)
        scl_freq : integer := 100000   -- I2C:  phase_max = clk_freq / (4 * scl_freq)
    );
    port (
        clk              : in  std_logic;
        reset_n          : in  std_logic;
        protocol_sel_i   : in  std_logic_vector(1 downto 0); -- "00"=UART "01"=I2C "10"/"11"=reserved

        tick_uart_o      : out std_logic; -- 16x tick, gated to protocol_sel_i = "00"
        tick_i2c_o       : out std_logic; -- 4x phase tick, gated to protocol_sel_i = "01"
        engines_reset_n_o : out std_logic -- reset_n, plus a 1-cycle pulse on every protocol switch
    );
end tick_gen;

architecture rtl of tick_gen is
    constant uart_tick_max : integer := clk_freq / (16 * baudrate);
    constant i2c_phase_max : integer := clk_freq / (4 * scl_freq);

    signal cnt_q      : unsigned(9 downto 0);
    -- Initialized to uart_tick_max (rather than defaulting to the range's
    -- left bound, 0) so the very first delta cycle -- before this signal's
    -- own driver below has had a chance to run -- never computes
    -- thresh_max - 1 = -1 into the to_unsigned() conversion.
    signal thresh_max  : integer range 0 to 1023 := uart_tick_max;
    signal tick_raw    : std_logic;

    -- protocol_sel_i one cycle ago, and the change flag derived from it.
    signal proto_sel_q  : std_logic_vector(1 downto 0);
    signal proto_changed : std_logic;

begin

    -- Threshold mux: same two constants each original module already
    -- computes from its own generics, just selected at runtime instead of
    -- being the only option. The reserved codes fall back to the UART
    -- threshold; it never matters, since tick_raw is gated off below for
    -- any protocol_sel_i other than "00"/"01".
    thresh_max <= i2c_phase_max when protocol_sel_i = "01" else uart_tick_max;

    p_cnt_q : process (clk, reset_n)
    begin
        if (reset_n = '0') then
            cnt_q      <= (others => '0');
            -- Seeded to the current protocol_sel_i (not left at 'U'/"00")
            -- so releasing reset never mistakes "startup" for "just switched".
            proto_sel_q <= protocol_sel_i;
        elsif rising_edge(clk) then
            if (cnt_q /= to_unsigned(thresh_max - 1, cnt_q'length)) then
                cnt_q <= cnt_q + 1;
            else
                cnt_q <= (others => '0');
            end if;
            proto_sel_q <= protocol_sel_i;
        end if;
    end process p_cnt_q;

    -- Outside the process, direct assignment (mirrors cnt.vhd / i2c_clk_div.vhd):
    tick_raw <= '1' when (cnt_q = to_unsigned(thresh_max - 1, cnt_q'length)) else '0';

    -- Gate: only the currently-selected protocol ever sees a tick.
    tick_uart_o <= tick_raw when protocol_sel_i = "00" else '0';
    tick_i2c_o  <= tick_raw when protocol_sel_i = "01" else '0';

    -- Edge detector: protocol_sel_i vs. its value one cycle ago.
    proto_changed <= '1' when protocol_sel_i /= proto_sel_q else '0';

    -- Combined reset for the protocol engines: the external reset_n, ANDed
    -- with a 1-cycle-wide low pulse on every protocol_sel_i change.
    engines_reset_n_o <= reset_n and not proto_changed;

end rtl;
