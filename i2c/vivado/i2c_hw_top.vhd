-- =============================================================================
-- i2c_hw_top.vhd  (TMP102 version)
--
-- Same idea as the no-slave bring-up wrapper, but now driving a real TMP102
-- temperature sensor with two distinct, separately-triggered operations so
-- you can verify TRANSMIT and RECEIVE independently:
--
--   BTN(0) = WRITE  : single byte, value 0x00, to the TMP102's Pointer
--                     Register -> selects the Temperature register.
--                     Tests the master's transmit path: a real ACK from a
--                     real device (not a NACK) is what "correct" looks like
--                     here.
--
--   BTN(1) = READ   : two bytes back-to-back (MSB then LSB of the 12-bit
--                     temperature reading), master ACKs after the first
--                     byte and NACKs after the second to end the read, per
--                     the I2C spec. Tests the master's receive path and its
--                     multi-byte continuation logic (last_byte_i timing).
--
-- TMP102 reference (Table 4 / Table 7 / temperature format, TI/SparkFun
-- datasheet): 7-bit address is 0x48 when ADD0 is tied to GND (the common
-- default on most breakout boards), pointer value 0x00 selects
-- the Temperature register (which also happens to be the power-on default,
-- but we still write it explicitly to exercise the transmit path), and the
-- temperature register is 12-bit two's complement: byte1 = T11..T4,
-- byte2 = T3..T0 followed by 4 zero bits, 0.0625 degC per LSB.
--
-- If your specific TMP102 breakout ties ADD0 somewhere other than GND
-- (V+, SDA, or SCL), change the addr_i constant below to match (Table 4):
--   ADD0->GND : "1001000" (0x48, used below)
--   ADD0->V+  : "1001001" (0x49)
--   ADD0->SDA : "1001010" (0x4A)
--   ADD0->SCL : "1001011" (0x4B)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_hw_top is
    port (
        CLK100MHZ  : in    std_logic;
        CPU_RESETN : in    std_logic;
        BTN        : in    std_logic_vector(3 downto 0);  -- BTN(0)=write pointer, BTN(1)=read 2 bytes
        SW         : in    std_logic_vector(3 downto 0);  -- currently unused
        LED        : out   std_logic_vector(3 downto 0);
        JA         : inout std_logic_vector(1 downto 0)   -- JA(0)=SCL, JA(1)=SDA
    );
end entity i2c_hw_top;

architecture struct of i2c_hw_top is

    component i2c_top is
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
            sda_io        : inout std_logic;
            scl_io        : inout std_logic
        );
    end component;

    signal busy_w, done_w, ack_err_w : std_logic;
    signal rdata_w                   : std_logic_vector(7 downto 0);

    -- BTN(0)/BTN(1) synchronizers + one-shot edge detectors
    signal btn0_ff0, btn0_ff1, btn0_ff2 : std_logic;
    signal btn1_ff0, btn1_ff1, btn1_ff2 : std_logic;
    signal op_write_pulse, op_read_pulse : std_logic;

    -- Transaction sequencing: which op is in flight
    signal op_is_read   : std_logic;  -- registered: '1' for the duration of a read transaction
    signal is_read_now_c : std_logic; -- combinational: op_is_read, but valid on the trigger cycle itself
    signal last_byte_i_w : std_logic; -- combinational: what we feed i2c_top's last_byte_i

    -- Sticky, human-visible copies of done_o / ack_err_o
    signal done_latched, ack_err_latched : std_logic;

    -- Heartbeat
    signal heartbeat_cnt : unsigned(26 downto 0);

begin

    -- 1. Synchronize both buttons into the clk domain, one-shot edge detect
    p_btn_sync : process (CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            btn0_ff0 <= BTN(0); btn0_ff1 <= btn0_ff0; btn0_ff2 <= btn0_ff1;
            btn1_ff0 <= BTN(1); btn1_ff1 <= btn1_ff0; btn1_ff2 <= btn1_ff1;
        end if;
    end process p_btn_sync;

    op_write_pulse <= btn0_ff1 and (not btn0_ff2);
    op_read_pulse  <= btn1_ff1 and (not btn1_ff2);

    -- 2. Track which operation is running, for the duration of the transaction
    p_op_track : process (CLK100MHZ, CPU_RESETN)
    begin
        if CPU_RESETN = '0' then
            op_is_read <= '0';
        elsif rising_edge(CLK100MHZ) then
            if op_write_pulse = '1' then
                op_is_read <= '0';
            elsif op_read_pulse = '1' then
                op_is_read <= '1';
            end if;
        end if;
    end process p_op_track;

    is_read_now_c <= '1' when op_read_pulse = '1' else
                      '0' when op_write_pulse = '1' else
                      op_is_read;

    -- 3. Compute last_byte_i.
    --
    --    Timing note (this is the part that's easy to get wrong): i2c_master
    --    samples last_byte_i to decide "is the NEXT byte the last one" at the
    --    SAME clock edge it asserts done_o for the CURRENT byte, and it uses
    --    the value last_byte_i held going INTO that edge -- not whatever it
    --    changes to afterward. So anything that reacts to seeing done_o go
    --    high (like a byte counter clocked off done_o) is structurally one
    --    cycle too late to affect that specific decision; it ends up
    --    terminating the read one byte later than intended.
    --
    --    The robust fix: don't react to done_o at all. We know in advance
    --    we want exactly 2 bytes, so last_byte_i only needs to be '0' for
    --    the single cycle the read starts (byte 1 must not be marked last)
    --    and '1' at every other moment, including immediately afterward --
    --    long before byte 1's own done_o even fires. That way it's already
    --    settled to '1' by the time byte 1's decision reads it, correctly
    --    marking byte 2 as the last one; and byte 2's own decision then
    --    reads last_q='1' (latched during byte 1's decision) and stops.
    last_byte_i_w <= '1' when is_read_now_c = '0' else  -- write: always single-byte
                      '0' when op_read_pulse = '1' else -- read, starting now: byte 1 is not last
                      '1';                                -- read, any other time: already marking byte 2 last

    -- 4. i2c_top instance
    u_i2c_top : i2c_top
        port map (
            clk         => CLK100MHZ,
            reset_n     => CPU_RESETN,

            start_i     => (op_write_pulse or op_read_pulse),
            addr_i      => "1001000",       -- TMP102, ADD0 -> GND (0x48)
            rw_i        => op_read_pulse,   -- '1' only during the read trigger cycle, which is
                                             -- exactly when i2c_master latches it -- see i2c_hw_top note
            wdata_i     => "00000000",      -- pointer value 0x00 = Temperature register
            last_byte_i => last_byte_i_w,
            rdata_o     => rdata_w,
            done_o      => done_w,
            busy_o      => busy_w,
            ack_err_o   => ack_err_w,

            sda_io      => JA(1),
            scl_io      => JA(0)
        );

    -- 5. Stretch done_o / ack_err_o onto sticky LEDs
    p_latch : process (CLK100MHZ, CPU_RESETN)
    begin
        if CPU_RESETN = '0' then
            done_latched    <= '0';
            ack_err_latched <= '0';
        elsif rising_edge(CLK100MHZ) then
            if (op_write_pulse = '1' or op_read_pulse = '1') then
                done_latched    <= '0';
                ack_err_latched <= '0';
            elsif done_w = '1' then
                done_latched    <= '1';
                ack_err_latched <= ack_err_w;
            end if;
        end if;
    end process p_latch;

    -- 6. Heartbeat
    p_heartbeat : process (CLK100MHZ, CPU_RESETN)
    begin
        if CPU_RESETN = '0' then
            heartbeat_cnt <= (others => '0');
        elsif rising_edge(CLK100MHZ) then
            heartbeat_cnt <= heartbeat_cnt + 1;
        end if;
    end process p_heartbeat;

    -- LED mapping:
    --   LED0 = heartbeat (design alive)
    --   LED1 = last operation completed at least one byte (sticky)
    --   LED2 = that operation's most recent ACK/NACK result: OFF = ACK (real
    --          device answered!), ON = NACK (no answer / wrong address /
    --          wiring problem) -- this is your main go/no-go indicator now
    --   LED3 = raw busy_o (too fast to see, informational only)
    LED(0) <= heartbeat_cnt(26);
    LED(1) <= done_latched;
    LED(2) <= ack_err_latched;
    LED(3) <= busy_w;

end architecture struct;
