library ieee;
use ieee.std_logic_1164.all;

-- Self-contained loopback variant: same cnt + uart_rx + uart_tx pair as
-- uart_top.vhd, but with rx_done_o/rx_data_o wired straight into
-- tx_start_i/tx_byte_i internally, so any byte received on rx_pin_i is
-- automatically echoed back out tx_pin_o. This exists purely as a
-- self-contained hardware test harness (see docs/uart_hw_bringup.md) --
-- for driving TX/RX independently from an actual host, use uart_top.vhd
-- instead.
entity uart_loopback_top is
    port (
        clk      : in  std_logic;
        reset_n  : in  std_logic;
        rx_pin_i : in  std_logic; -- Physical receive pin from the PC
        tx_pin_o : out std_logic  -- Physical transmit pin to the PC
    );
end uart_loopback_top;

architecture struct of uart_loopback_top is

    -- 1. COMPONENT DECLARATIONS
    component cnt is
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
    signal w_data    : std_logic_vector(7 downto 0);
    signal w_done    : std_logic;

    -- Optional signals left dangling (open) for now
    signal w_err     : std_logic;
    signal w_busy    : std_logic;

begin

    -- 3. INSTANTIATION AND MAPPING
    u_baud_gen : cnt
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
            rx_data_o => w_data,
            rx_done_o => w_done,
            rx_err_o  => w_err
        );

    u_transmitter : uart_tx
        port map (
            clk        => clk,
            reset_n    => reset_n,
            tx_start_i => w_done,    -- The RX triggers the TX!
            tx_byte_i  => w_data,    -- The RX passes the byte to the TX
            tick_16_i  => w_tick_16,
            tx_o       => tx_pin_o,
            tx_busy_o  => w_busy
        );

end struct;
