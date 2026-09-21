library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_master is
    port (
        clk           : in  std_logic;
        reset_n       : in  std_logic;

        -- Host control interface
        start_i       : in  std_logic;                     -- pulse: begin a new transaction
        addr_i        : in  std_logic_vector(6 downto 0);  -- slave address
        rw_i          : in  std_logic;                     -- '0' = write, '1' = read
        wdata_i       : in  std_logic_vector(7 downto 0);  -- byte to write (sampled at start_i and at each done_o)
        last_byte_i   : in  std_logic;                     -- '1' = this is the last byte of the transaction
        rdata_o       : out std_logic_vector(7 downto 0);  -- last byte read
        done_o        : out std_logic;                     -- pulse: one byte completed (ack sampled/emitted)
        busy_o        : out std_logic;
        ack_err_o     : out std_logic;                     -- '1' = last ack seen on the bus was a NACK

        -- Phase generator input, same role as tick_16_i in the UART
        tick_4_i      : in  std_logic;

        -- I2C bus, open-drain lines resolved at the top level
        sda_i         : in  std_logic;
        sda_o         : out std_logic;
        sda_oe_o      : out std_logic;
        scl_i         : in  std_logic;
        scl_o         : out std_logic;
        scl_oe_o      : out std_logic
    );
end i2c_master;

architecture rtl of i2c_master is

    type t_state is (idle, start_cond, address, addr_ack, data, data_ack, stop_cond);
    signal state       : t_state;

    signal quarter_cnt : unsigned(1 downto 0); -- t1..t4 phase within the current bit
    signal bit_cnt      : unsigned(2 downto 0); -- 7 downto 0, MSB first

    signal shift_reg    : std_logic_vector(7 downto 0);
    signal rw_q         : std_logic; -- latched direction for the whole transaction
    signal last_q       : std_logic; -- latched last_byte_i for the current byte

begin

    busy_o <= '0' when state = idle else '1';

    p_i2c_core : process(clk, reset_n)
    begin
        if reset_n = '0' then
            state       <= idle;
            quarter_cnt <= (others => '0');
            bit_cnt     <= (others => '0');
            shift_reg   <= (others => '0');
            rw_q        <= '0';
            last_q      <= '0';
            rdata_o     <= (others => '0');
            done_o      <= '0';
            ack_err_o   <= '0';
            sda_o       <= '1';
            sda_oe_o    <= '0';
            scl_o       <= '1';
            scl_oe_o    <= '0';

        elsif rising_edge(clk) then

            -- done_o is a one-cycle pulse; turned off unless set explicitly below
            done_o <= '0';

            case state is

                when idle =>
                    sda_oe_o  <= '0'; -- bus released, pull-ups hold it at '1'
                    scl_oe_o  <= '0';
                    ack_err_o <= '0';
                    if start_i = '1' then
                        shift_reg   <= addr_i & rw_i; -- 7-bit address + R/W, MSB first
                        bit_cnt     <= "111";
                        quarter_cnt <= (others => '0');
                        rw_q        <= rw_i;
                        last_q      <= last_byte_i;
                        state       <= start_cond;
                    end if;

                when start_cond =>
                    -- SDA falls while SCL is still high (released) -> START condition
                    scl_oe_o <= '0';
                    sda_oe_o <= '1';
                    sda_o    <= '0';
                    if tick_4_i = '1' then
                        if quarter_cnt = 3 then
                            quarter_cnt <= (others => '0');
                            state       <= address;
                        else
                            quarter_cnt <= quarter_cnt + 1;
                        end if;
                    end if;

                when address =>
                    if tick_4_i = '1' then
                        if quarter_cnt = 0 then
                            -- t1: force SCL low, then update SDA to the new bit
                            -- (SDA must only change while SCL is low, or it looks like START/STOP)
                            scl_oe_o    <= '1';
                            scl_o       <= '0';
                            sda_oe_o    <= '1';
                            sda_o       <= shift_reg(7); -- MSB first
                            quarter_cnt <= quarter_cnt + 1;
                        elsif quarter_cnt = 1 then
                            -- t2: release SCL; if the slave holds it low, stall here (clock stretching)
                            scl_oe_o <= '0';
                            if scl_i = '1' then
                                quarter_cnt <= quarter_cnt + 1;
                            end if;
                        elsif quarter_cnt = 2 then
                            -- t3: SCL stable high, bit is valid on the bus
                            quarter_cnt <= quarter_cnt + 1;
                        else
                            -- t4: end of bit
                            if bit_cnt = 0 then
                                quarter_cnt <= (others => '0');
                                state       <= addr_ack;
                            else
                                bit_cnt     <= bit_cnt - 1;
                                shift_reg   <= shift_reg(6 downto 0) & '0';
                                quarter_cnt <= (others => '0');
                            end if;
                        end if;
                    end if;

                when addr_ack =>
                    if tick_4_i = '1' then
                        if quarter_cnt = 0 then
                            -- release SDA (while SCL is low) so the slave can drive the ack
                            scl_oe_o    <= '1';
                            scl_o       <= '0';
                            sda_oe_o    <= '0';
                            quarter_cnt <= quarter_cnt + 1;
                        elsif quarter_cnt = 1 then
                            scl_oe_o <= '0';
                            if scl_i = '1' then
                                quarter_cnt <= quarter_cnt + 1;
                            end if;
                        elsif quarter_cnt = 2 then
                            -- t3: sample point for the ack bit
                            ack_err_o   <= sda_i; -- '0' = ACK, '1' = NACK
                            quarter_cnt <= quarter_cnt + 1;
                        else
                            quarter_cnt <= (others => '0');
                            if sda_i = '1' then
                                -- address NACK: no slave answered, abort the transaction
                                state <= stop_cond;
                            else
                                bit_cnt <= "111";
                                if rw_q = '0' then
                                    shift_reg <= wdata_i;
                                else
                                    shift_reg <= (others => '0');
                                end if;
                                state <= data;
                            end if;
                        end if;
                    end if;

                when data =>
                    if rw_q = '1' then
                        sda_oe_o <= '0'; -- read: the slave drives SDA
                    end if;
                    if tick_4_i = '1' then
                        if quarter_cnt = 0 then
                            scl_oe_o <= '1';
                            scl_o    <= '0';
                            if rw_q = '0' then
                                -- SDA must only change while SCL is low
                                sda_oe_o <= '1';
                                sda_o    <= shift_reg(7); -- MSB first
                            end if;
                            quarter_cnt <= quarter_cnt + 1;
                        elsif quarter_cnt = 1 then
                            scl_oe_o <= '0';
                            if scl_i = '1' then
                                quarter_cnt <= quarter_cnt + 1;
                            end if;
                        elsif quarter_cnt = 2 then
                            if rw_q = '1' then
                                shift_reg <= shift_reg(6 downto 0) & sda_i; -- capture incoming bit
                            end if;
                            quarter_cnt <= quarter_cnt + 1;
                        else
                            if bit_cnt = 0 then
                                quarter_cnt <= (others => '0');
                                state       <= data_ack;
                            else
                                bit_cnt <= bit_cnt - 1;
                                if rw_q = '0' then
                                    shift_reg <= shift_reg(6 downto 0) & '0';
                                end if;
                                quarter_cnt <= (others => '0');
                            end if;
                        end if;
                    end if;

                when data_ack =>
                    if tick_4_i = '1' then
                        if quarter_cnt = 0 then
                            -- SDA must only change while SCL is low
                            scl_oe_o <= '1';
                            scl_o    <= '0';
                            if rw_q = '0' then
                                sda_oe_o <= '0'; -- write: release SDA to read the slave's ack
                            else
                                sda_oe_o <= '1'; -- read: the master drives ack/nack
                                sda_o    <= last_q; -- '0' = ACK (want more bytes), '1' = NACK (last byte)
                            end if;
                            quarter_cnt <= quarter_cnt + 1;
                        elsif quarter_cnt = 1 then
                            scl_oe_o <= '0';
                            if scl_i = '1' then
                                quarter_cnt <= quarter_cnt + 1;
                            end if;
                        elsif quarter_cnt = 2 then
                            if rw_q = '0' then
                                ack_err_o <= sda_i; -- slave's ack/nack after a write
                            end if;
                            if rw_q = '1' then
                                rdata_o <= shift_reg; -- publish the byte just read
                            end if;
                            quarter_cnt <= quarter_cnt + 1;
                        else
                            quarter_cnt <= (others => '0');
                            done_o      <= '1'; -- one byte completed
                            if last_q = '1' or (rw_q = '0' and sda_i = '1') then
                                state <= stop_cond;
                            else
                                bit_cnt <= "111";
                                last_q  <= last_byte_i; -- host is expected to update wdata_i/last_byte_i on done_o
                                if rw_q = '0' then
                                    shift_reg <= wdata_i;
                                else
                                    shift_reg <= (others => '0');
                                end if;
                                state <= data;
                            end if;
                        end if;
                    end if;

                when stop_cond =>
                    -- SCL goes high first while SDA is still low, then SDA rises -> STOP condition
                    if tick_4_i = '1' then
                        if quarter_cnt = 0 then
                            scl_oe_o    <= '1';
                            scl_o       <= '0';
                            sda_oe_o    <= '1';
                            sda_o       <= '0';
                            quarter_cnt <= quarter_cnt + 1;
                        elsif quarter_cnt = 1 then
                            scl_oe_o <= '0'; -- release SCL, pulled up to '1'
                            if scl_i = '1' then
                                quarter_cnt <= quarter_cnt + 1;
                            end if;
                        elsif quarter_cnt = 2 then
                            sda_oe_o    <= '1';
                            sda_o       <= '1'; -- SDA rises while SCL is high -> STOP
                            quarter_cnt <= quarter_cnt + 1;
                        else
                            sda_oe_o    <= '0'; -- release the bus
                            quarter_cnt <= (others => '0');
                            state       <= idle;
                        end if;
                    end if;

                when others =>
                    state <= idle;

            end case;
        end if;
    end process p_i2c_core;

end rtl;