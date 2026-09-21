library ieee;
use ieee.std_logic_1164.all;

entity i2c_top is
    port (
        clk           : in  std_logic;
        reset_n       : in  std_logic;

        -- Host control interface
        start_i       : in  std_logic;
        addr_i        : in  std_logic_vector(6 downto 0);
        rw_i          : in  std_logic;
        wdata_i       : in  std_logic_vector(7 downto 0);
        last_byte_i   : in  std_logic;
        rdata_o       : out std_logic_vector(7 downto 0);
        done_o        : out std_logic;
        busy_o        : out std_logic;
        ack_err_o     : out std_logic;

        -- Physical I2C bus pins (require external pull-up resistors,
        -- either on the board or enabled via the PULLUP=TRUE constraint)
        sda_io        : inout std_logic;
        scl_io        : inout std_logic
    );
end i2c_top;

architecture struct of i2c_top is

    -- 1. COMPONENT DECLARATIONS
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

    -- 2. INTERNAL WIRING
    signal w_tick_4 : std_logic;

    signal w_sda_i, w_sda_o, w_sda_oe_o : std_logic;
    signal w_scl_i, w_scl_o, w_scl_oe_o : std_logic;

begin

    -- 3. INSTANTIATION AND MAPPING
    u_scl_gen : i2c_clk_div
        port map (
            clk      => clk,
            reset_n  => reset_n,
            tick_4_o => w_tick_4
        );

    u_i2c : i2c_master
        port map (
            clk         => clk,
            reset_n     => reset_n,

            start_i     => start_i,
            addr_i      => addr_i,
            rw_i        => rw_i,
            wdata_i     => wdata_i,
            last_byte_i => last_byte_i,
            rdata_o     => rdata_o,
            done_o      => done_o,
            busy_o      => busy_o,
            ack_err_o   => ack_err_o,

            tick_4_i    => w_tick_4,

            sda_i       => w_sda_i,
            sda_o       => w_sda_o,
            sda_oe_o    => w_sda_oe_o,
            scl_i       => w_scl_i,
            scl_o       => w_scl_o,
            scl_oe_o    => w_scl_oe_o
        );

    -- 4. OPEN-DRAIN BUFFERS (mandatory at this top level: this is where the
    -- sda_o/sda_oe_o pair becomes a real bidirectional physical pin).
    -- Only '0' is ever actively driven; for '1' the line is released to
    -- high impedance and the external pull-up resistor pulls it up.
    -- An active '1' is never driven, so several masters/slaves can coexist.
    sda_io <= '0' when (w_sda_oe_o = '1' and w_sda_o = '0') else 'Z';
    scl_io <= '0' when (w_scl_oe_o = '1' and w_scl_o = '0') else 'Z';

    -- Input buffer model: a real pin never sees the pull-up's "weak"
    -- 'H'/'L' value -- the input comparator always resolves to a clean
    -- '0'/'1'. to_x01 reproduces that in simulation too (i2c_master compares
    -- scl_i/sda_i with strict '=').
    w_sda_i <= to_x01(sda_io);
    w_scl_i <= to_x01(scl_io);

end struct;
