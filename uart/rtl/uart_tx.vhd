library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
    port (
        clk           : in  std_logic;
        reset_n       : in  std_logic;
        tx_start_i    : in  std_logic;
        tx_byte_i     : in  std_logic_vector(7 downto 0);
        tick_16_i     : in  std_logic; -- Clean tick from the counter

        tx_o          : out std_logic;
        tx_busy_o     : out std_logic
    );
end uart_tx;

architecture rtl of uart_tx is
    type t_state is (idle, start_bit, data_bits, parity_bit, end_bit);
    signal state     : t_state := idle;

    signal tick_cnt  : unsigned(3 downto 0) := (others => '0');
    signal bit_cnt   : unsigned(2 downto 0) := (others => '0');
    signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal parity_q  : std_logic := '0';
begin

    tx_busy_o <= '0' when (state = idle) else '1';

    p_tx_core : process(clk, reset_n)
    begin
        if reset_n = '0' then
            state     <= idle;
            tick_cnt  <= (others => '0');
            bit_cnt   <= (others => '0');
            shift_reg <= (others => '0');
            parity_q  <= '0';
            tx_o      <= '1';
        elsif rising_edge(clk) then

            case state is

                when idle =>
                    tx_o <= '1';
                    if tx_start_i = '1' then
                        shift_reg <= tx_byte_i;
                        parity_q  <= tx_byte_i(0) xor tx_byte_i(1) xor tx_byte_i(2) xor tx_byte_i(3) xor
                                     tx_byte_i(4) xor tx_byte_i(5) xor tx_byte_i(6) xor tx_byte_i(7);
                        tick_cnt  <= (others => '0');
                        bit_cnt   <= (others => '0');
                        state     <= start_bit;
                    end if;

                when start_bit =>
                    tx_o <= '0'; -- Start bit
                    if tick_16_i = '1' then
                        if tick_cnt = 15 then
                            tick_cnt <= (others => '0');
                            state    <= data_bits;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;
                    end if;

                when data_bits =>
                    tx_o <= shift_reg(0);
                    if tick_16_i = '1' then
                        if tick_cnt = 15 then
                            tick_cnt <= (others => '0');
                            if bit_cnt = 7 then
                                state <= parity_bit;
                            else
                                bit_cnt   <= bit_cnt + 1;
                                shift_reg <= '0' & shift_reg(7 downto 1); -- Standard shift register
                            end if;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;
                    end if;

                when parity_bit =>
                    tx_o <= parity_q; -- Send the registered parity bit
                    if tick_16_i = '1' then
                        if tick_cnt = 15 then
                            tick_cnt <= (others => '0');
                            state    <= end_bit;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;
                    end if;

                when end_bit =>
                    tx_o <= '1'; -- Stop bit
                    if tick_16_i = '1' then
                        if tick_cnt = 15 then
                            state <= idle;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;
                    end if;

                when others =>
                    state <= idle;
            end case;
        end if;
    end process p_tx_core;

end rtl;