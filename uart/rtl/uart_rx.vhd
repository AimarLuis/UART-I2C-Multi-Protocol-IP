library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
    port (
        clk           : in  std_logic;
        reset_n       : in  std_logic;
        rx_i          : in  std_logic;
        tick_16_i     : in  std_logic;

        rx_data_o     : out std_logic_vector(7 downto 0);
        rx_done_o     : out std_logic;
        rx_err_o      : out std_logic
    );
end uart_rx;

architecture rtl of uart_rx is
    type t_state is (idle, start_bit, data_bits, parity_bit, end_bit);
    signal state     : t_state;

    signal tick_cnt  : unsigned(3 downto 0);
    signal bit_cnt   : unsigned(2 downto 0);
    signal shift_reg : std_logic_vector(7 downto 0);
    signal parity_q  : std_logic;

    -- Internal signal to remember whether a parity error occurred before reaching STOP
    signal err_flag  : std_logic;

begin

    p_rx_core : process(clk, reset_n)
    begin
        if reset_n = '0' then
            state     <= idle;
            tick_cnt  <= (others => '0');
            bit_cnt   <= (others => '0');
            shift_reg <= (others => '0');
            parity_q  <= '0';
            rx_data_o <= (others => '0');
            rx_done_o <= '0';
            rx_err_o  <= '0';
            err_flag  <= '0';

        elsif rising_edge(clk) then

            -- By default, pulses last a single cycle.
            -- If we don't explicitly re-assert them below, they turn off.
            rx_done_o <= '0';
			rx_err_o  <= '0';

            case state is

                when idle =>
                    rx_err_o <= '0'; -- Clear errors from the previous frame
                    err_flag <= '0';
                    if rx_i = '0' then
                        tick_cnt <= (others => '0');
                        bit_cnt  <= (others => '0');
						shift_reg <= (others => '0');
                        state    <= start_bit;
                    end if;

                when start_bit =>
                    if tick_16_i = '1' then
                        if tick_cnt = 7 then
                            tick_cnt <= (others => '0');
                            if rx_i = '0' then
                                state <= data_bits;
                            else
                                state <= idle;
                            end if;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;
                    end if;

                when data_bits =>
                    if tick_16_i = '1' then
                        if tick_cnt = 15 then
                            tick_cnt <= (others => '0');
                            -- ALWAYS store the bit, whether it's the last one or not!
                            shift_reg <= rx_i & shift_reg(7 downto 1);

                            if bit_cnt = 7 then
                                -- If this is bit 7, compute parity right now
                                parity_q <= (rx_i xor shift_reg(7) xor shift_reg(6) xor shift_reg(5) xor
                                             shift_reg(4) xor shift_reg(3) xor shift_reg(2) xor shift_reg(1));
                                state <= parity_bit;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;
                    end if;

                when parity_bit =>
                    if tick_16_i = '1' then
                        if tick_cnt = 15 then
                            tick_cnt <= (others => '0');
                            -- Compare what was received on rx_i against the computed value
                            if rx_i /= parity_q then
                                err_flag <= '1'; -- Flag the error, but do NOT abort
                            end if;
                            state <= end_bit;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;
                    end if;

                when end_bit =>
                    if tick_16_i = '1' then
                        if tick_cnt = 15 then
                            if rx_i = '1' and err_flag = '0' then
                                -- Everything is fine
                                rx_data_o <= shift_reg;
                                rx_done_o <= '1';
                                rx_err_o  <= '0';
                            else
                                -- Parity error or framing error
                                rx_err_o  <= '1';
                            end if;
                            state <= idle;
                        else
                            tick_cnt <= tick_cnt + 1;
                        end if;
                    end if;

                when others =>
                    state <= idle;
            end case;
        end if;
    end process p_rx_core;

end rtl;