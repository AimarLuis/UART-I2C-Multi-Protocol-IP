library ieee;
use ieee.std_logic_1164.all;

-- Structural pair of cnt + uart_rx + uart_tx (one shared baud generator),
-- wired for genuine two-way use from an external host: tx_start_i/tx_byte_i
-- are real input ports (drive them to send a byte) and
-- rx_data_o/rx_done_o/rx_err_o are real output ports (read them to see
-- what was received), rather than being wired to each other internally.
-- uart_rx/uart_tx/cnt are unmodified and reused exactly as in
-- uart_loopback_top.vhd, the self-contained echo variant used for a
-- standalone hardware test (see docs/uart_hw_bringup.md) -- use that one
-- instead if you just want a plug-in loopback test harness with no host
-- logic of your own driving it.
entity uart_top is
    generic (
        clk_freq : integer := 100000000;
        baudrate : integer := 9600
    );
    port (
        clk        : in  std_logic;
        reset_n    : in  std_logic;

        -- Physical UART pins
        rx_pin_i   : in  std_logic; -- Physical receive pin from the PC
        tx_pin_o   : out std_logic; -- Physical transmit pin to the PC

        -- Host TX interface: drive a byte out
        tx_start_i : in  std_logic;
        tx_byte_i  : in  std_logic_vector(7 downto 0);
        tx_busy_o  : out std_logic;

        -- Host RX interface: read back whatever was received
        rx_data_o  : out std_logic_vector(7 downto 0);
        rx_done_o  : out std_logic;
        rx_err_o   : out std_logic
    );
end uart_top;

architecture struct of uart_top is

    -- 1. COMPONENT DECLARATIONS
    component cnt is
        generic (
            clk_freq : integer := 100000000;
            baudrate : integer := 9600
        );
        port (clk : in std_logic; reset_n : in std_logic; tick_16_o : out std_logic);
    end component;

    component uart_rx is
        port (
            clk : in std_logic; reset_n : in std_logic; rx_i : in std_logic;
            tick_16_i : in std_logic; rx_data_o : out std_logic_vector(7 downto 0);
            rx_done_o : out std_logic; rx_err_o : out std_logic
        );
    end component;

    component uart_tx is
        port (
            clk : in std_logic; reset_n : in std_logic; tx_start_i : in std_logic;
            tx_byte_i : in std_logic_vector(7 downto 0); tick_16_i : in std_logic;
            tx_o : out std_logic; tx_busy_o : out std_logic
        );
    end component;

    -- 2. INTERNAL WIRING
    signal w_tick_16 : std_logic;

begin

    -- 3. INSTANTIATION AND MAPPING
    u_baud_gen : cnt
        generic map (
            clk_freq => clk_freq,
            baudrate => baudrate
        )
        port map (
            clk       => clk,
            reset_n   => reset_n,
            tick_16_o => w_tick_16
        );

    u_receiver : uart_rx
        port map (
            clk       => clk,
            reset_n   => reset_n,
            rx_i      => rx_pin_i,
            tick_16_i => w_tick_16,
            rx_data_o => rx_data_o,
            rx_done_o => rx_done_o,
            rx_err_o  => rx_err_o
        );

    u_transmitter : uart_tx
        port map (
            clk        => clk,
            reset_n    => reset_n,
            tx_start_i => tx_start_i, -- host drives this directly, not the RX
            tx_byte_i  => tx_byte_i,  -- host drives this directly, not the RX
            tick_16_i  => w_tick_16,
            tx_o       => tx_pin_o,
            tx_busy_o  => tx_busy_o
        );

end struct;
