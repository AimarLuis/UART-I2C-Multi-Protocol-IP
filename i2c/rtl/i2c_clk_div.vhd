library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_clk_div is
    generic (
        clk_freq : integer := 100000000;
        scl_freq : integer := 100000
    );
    port (
        clk      : in std_logic;
        reset_n  : in std_logic;
        tick_4_o : out std_logic -- one clock-cycle pulse, 4 pulses per SCL period
    );
end i2c_clk_div;

architecture rtl of i2c_clk_div is
    constant phase_max : integer := clk_freq / (4 * scl_freq);

    signal cnt_q : unsigned(9 downto 0);

begin

    p_cnt_q : process (clk, reset_n)
    begin
        if (reset_n = '0') then
            cnt_q <= (others => '0');
        elsif clk'event and clk = '1' then
            if (cnt_q /= (phase_max - 1)) then
                cnt_q <= cnt_q + 1;
            else
                cnt_q <= (others => '0');
            end if;
        end if;
    end process p_cnt_q;

    -- Outside the process, direct assignment:
    tick_4_o <= '1' when (cnt_q = phase_max - 1) else '0';

end rtl;
