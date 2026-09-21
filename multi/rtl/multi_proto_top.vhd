library ieee;
use ieee.std_logic_1164.all;

-- Shared multi-protocol top level: one UART engine (uart_rx + uart_tx,
-- exposing the full host interface, same as uart_top.vhd) and one I2C
-- engine (i2c_master, same as i2c_top.vhd), both reusing the existing,
-- unmodified entities. The only new hardware is tick_gen, the
-- shared/gated tick source described in multi_proto_report.md.
--
-- protocol_sel_i selects which engine receives ticks and which engine's
-- bus lines are allowed to drive (oe asserted): "00" = UART, "01" = I2C,
-- "10"/"11" = reserved, no protocol active. Switching protocol_sel_i
-- mid-transaction is not supported -- see the report for details.
entity multi_proto_top is
    generic (
        clk_freq : integer := 100000000;
        baudrate : integer := 9600;
        scl_freq : integer := 100000
    );
    port (
        clk            : in  std_logic;
        reset_n        : in  std_logic;
        protocol_sel_i : in  std_logic_vector(1 downto 0);

        -- UART logical lines (push-pull, but oe kept for interface
        -- consistency with I2C and for future pin-mux routing)
        tx_out_o       : out std_logic;
        tx_oe_o        : out std_logic;
        rx_in_i        : in  std_logic;

        -- UART host control interface (same shape as uart_rx/uart_tx/uart_top)
        tx_start_i     : in  std_logic;
        tx_byte_i      : in  std_logic_vector(7 downto 0);
        tx_busy_o      : out std_logic;
        rx_data_o      : out std_logic_vector(7 downto 0);
        rx_done_o      : out std_logic;
        rx_err_o       : out std_logic;

        -- I2C host control interface (same shape as i2c_master/i2c_top)
        start_i        : in  std_logic;
        addr_i         : in  std_logic_vector(6 downto 0);
        rw_i           : in  std_logic;
        wdata_i        : in  std_logic_vector(7 downto 0);
        last_byte_i    : in  std_logic;
        rdata_o        : out std_logic_vector(7 downto 0);
        done_o         : out std_logic;
        busy_o         : out std_logic;
        ack_err_o      : out std_logic;

        -- I2C logical lines (open-drain: oe deasserted = released/high-Z)
        scl_out_o      : out std_logic;
        scl_oe_o       : out std_logic;
        scl_in_i       : in  std_logic;
        sda_out_o      : out std_logic;
        sda_oe_o       : out std_logic;
        sda_in_i       : in  std_logic
    );
end multi_proto_top;

architecture struct of multi_proto_top is

    -- 1. COMPONENT DECLARATIONS
    component tick_gen is
        generic (
            clk_freq : integer := 100000000;
            baudrate : integer := 9600;
            scl_freq : integer := 100000
        );
        port (
            clk              : in  std_logic;
            reset_n          : in  std_logic;
            protocol_sel_i   : in  std_logic_vector(1 downto 0);
            tick_uart_o      : out std_logic;
            tick_i2c_o       : out std_logic;
            engines_reset_n_o : out std_logic
        );
    end component;

    component uart_rx is
        port (
            clk       : in  std_logic;
            reset_n   : in  std_logic;
            rx_i      : in  std_logic;
            tick_16_i : in  std_logic;
            rx_data_o : out std_logic_vector(7 downto 0);
            rx_done_o : out std_logic;
            rx_err_o  : out std_logic
        );
    end component;

    component uart_tx is
        port (
            clk        : in  std_logic;
            reset_n    : in  std_logic;
            tx_start_i : in  std_logic;
            tx_byte_i  : in  std_logic_vector(7 downto 0);
            tick_16_i  : in  std_logic;
            tx_o       : out std_logic;
            tx_busy_o  : out std_logic
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
    signal w_tick_uart : std_logic;
    signal w_tick_i2c  : std_logic;
    -- reset_n plus a 1-cycle pulse every time protocol_sel_i changes;
    -- feeds the three engines' reset_n (not tick_gen's own, which still
    -- uses the external reset_n directly).
    signal w_engines_reset_n : std_logic;

    signal w_i2c_sda_o    : std_logic;
    signal w_i2c_sda_oe_o : std_logic;
    signal w_i2c_scl_o    : std_logic;
    signal w_i2c_scl_oe_o : std_logic;

begin

    -- 3. INSTANTIATION AND MAPPING

    -- Shared tick generator, already selected and gated on/off per
    -- protocol_sel_i.
    u_tick_gen : tick_gen
        generic map (
            clk_freq => clk_freq,
            baudrate => baudrate,
            scl_freq => scl_freq
        )
        port map (
            clk               => clk,
            reset_n           => reset_n,
            protocol_sel_i    => protocol_sel_i,
            tick_uart_o       => w_tick_uart,
            tick_i2c_o        => w_tick_i2c,
            engines_reset_n_o => w_engines_reset_n
        );

    -- UART engine: RX + TX exposed directly as a host interface, same as
    -- uart_top.vhd, except they now receive the shared/gated tick instead
    -- of their own private cnt, and their reset_n is the combined one
    -- (external + pulse on every protocol switch) instead of the raw
    -- external reset_n -- so a protocol_sel_i change always sends them
    -- back to idle, never resumes a parked state.
    u_receiver : uart_rx
        port map (
            clk       => clk,
            reset_n   => w_engines_reset_n,
            rx_i      => rx_in_i,
            tick_16_i => w_tick_uart,
            rx_data_o => rx_data_o,
            rx_done_o => rx_done_o,
            rx_err_o  => rx_err_o
        );

    u_transmitter : uart_tx
        port map (
            clk        => clk,
            reset_n    => w_engines_reset_n,
            tx_start_i => tx_start_i,
            tx_byte_i  => tx_byte_i,
            tick_16_i  => w_tick_uart,
            tx_o       => tx_out_o,
            tx_busy_o  => tx_busy_o
        );

    -- Push-pull: only asserted while UART is the active protocol, so a
    -- future pin-mux sees exactly one line being driven at a time.
    tx_oe_o <= '1' when protocol_sel_i = "00" else '0';

    -- I2C engine: i2c_master reused unmodified, receiving the shared tick
    -- on tick_4_i instead of its own private i2c_clk_div.
    u_i2c : i2c_master
        port map (
            clk           => clk,
            reset_n       => w_engines_reset_n,

            start_i       => start_i,
            addr_i        => addr_i,
            rw_i          => rw_i,
            wdata_i       => wdata_i,
            last_byte_i   => last_byte_i,
            rdata_o       => rdata_o,
            done_o        => done_o,
            busy_o        => busy_o,
            ack_err_o     => ack_err_o,

            tick_4_i      => w_tick_i2c,

            sda_i         => sda_in_i,
            sda_o         => w_i2c_sda_o,
            sda_oe_o      => w_i2c_sda_oe_o,
            scl_i         => scl_in_i,
            scl_o         => w_i2c_scl_o,
            scl_oe_o      => w_i2c_scl_oe_o
        );

    sda_out_o <= w_i2c_sda_o;
    scl_out_o <= w_i2c_scl_o;

    -- Same idea as tx_oe_o: oe is only let through while I2C is the active
    -- protocol, even though i2c_master already releases the bus (oe='0')
    -- at idle.
    sda_oe_o <= w_i2c_sda_oe_o when protocol_sel_i = "01" else '0';
    scl_oe_o <= w_i2c_scl_oe_o when protocol_sel_i = "01" else '0';

end struct;
