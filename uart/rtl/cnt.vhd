library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cnt is
    generic (
        clk_freq  : integer := 100000000;
        baudrate  : integer := 9600
    );
    port (
        clk       : in std_logic;
        reset_n   : in std_logic;
        tick_16_o : out std_logic -- single-cycle pulse output
    );
end cnt;

architecture rtl of cnt is
    constant tick_max : integer := clk_freq / (16 * baudrate);

    signal cnt_q : unsigned(9 downto 0);

begin

    p_cnt_q : process (clk, reset_n)
    begin
        if (reset_n = '0') then
            cnt_q <= (others => '0');
        elsif clk'event and clk = '1' then
            if (cnt_q /= (tick_max - 1)) then
                cnt_q <= cnt_q + 1;
            else
                cnt_q <= (others => '0');
            end if;
        end if;
    end process p_cnt_q;

    -- Outside the process, direct assignment:
    tick_16_o <= '1' when (cnt_q = tick_max - 1) else '0';

end rtl;