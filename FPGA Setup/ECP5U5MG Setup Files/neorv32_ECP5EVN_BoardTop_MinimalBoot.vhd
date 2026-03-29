-- #################################################################################################
-- # << NEORV32 - Example setup including the bootloader, for the ECP5EVN (c) Board >>             #
-- # ********************************************************************************************* #
-- # BSD 3-Clause License                                                                          #
-- #                                                                                               #
-- # Copyright (c) 2023, Stephan Nolting. All rights reserved.                                     #
-- #                                                                                               #
-- # Redistribution and use in source and binary forms, with or without modification, are          #
-- # permitted provided that the following conditions are met:                                     #
-- #                                                                                               #
-- # 1. Redistributions of source code must retain the above copyright notice, this list of        #
-- #    conditions and the following disclaimer.                                                   #
-- #                                                                                               #
-- # 2. Redistributions in binary form must reproduce the above copyright notice, this list of     #
-- #    conditions and the following disclaimer in the documentation and/or other materials        #
-- #    provided with the distribution.                                                            #
-- #                                                                                               #
-- # 3. Neither the name of the copyright holder nor the names of its contributors may be used to  #
-- #    endorse or promote products derived from this software without specific prior written      #
-- #    permission.                                                                                #
-- #                                                                                               #
-- # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS   #
-- # OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF               #
-- # MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE    #
-- # COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,     #
-- # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE #
-- # GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED    #
-- # AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING     #
-- # NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED  #
-- # OF THE POSSIBILITY OF SUCH DAMAGE.                                                            #
-- # ********************************************************************************************* #
-- # The NEORV32 Processor - https://github.com/stnolting/neorv32              (c) Stephan Nolting #
-- #################################################################################################

Library ieee;
Use ieee.std_logic_1164.All;
Use ieee.numeric_std.All;

Library neorv32;
Use neorv32.neorv32_package.All;

Entity neorv32_ECP5EVN_BoardTop_MinimalBoot Is
	Port (
		--Clock and Reset inputs
		ECP5EVN_CLK   : In    Std_logic;
		ECP5EVN_RST_N : In    Std_logic;

		--LED outputs for camera signal activity debug
		ECP5EVN_LED0  : Out   Std_logic; 
		ECP5EVN_LED1  : Out   Std_logic; 
		ECP5EVN_LED2  : Out   Std_logic; 
		ECP5EVN_LED3  : Out   Std_logic; 
		ECP5EVN_LED4  : Out   Std_logic;
		ECP5EVN_LED5  : Out   Std_logic;
		ECP5EVN_LED6  : Out   Std_logic;
		ECP5EVN_LED7  : Out   Std_logic;
		--UART0
		ECP5EVN_RX    : In    Std_logic;
		ECP5EVN_TX    : Out   Std_logic;

		--Camera interface
		SIO_C         : Inout Std_ulogic;
		SIO_D         : Inout Std_ulogic;
		VSYNC         : In    Std_ulogic; --Camera VSYNC signal
		HREF          : In    Std_ulogic; --Camera HREF signal
		PCLK          : In    Std_ulogic; --Camera PCLK signal
		XCLK          : Out   Std_ulogic; --Camera XCLK generated via PLL
		Data          : In    Std_ulogic_vector (7 Downto 0); --Camera data out pins
		OV5640_RESET  : Out   Std_ulogic; --Camera reset
		POWER_DOWN    : Out   Std_ulogic --Camera power down
	);
End Entity;

Architecture neorv32_ECP5EVN_BoardTop_MinimalBoot_rtl Of neorv32_ECP5EVN_BoardTop_MinimalBoot Is

	--Configuration: clock frequency in Hz (72 MHz system clock)
	Constant f_clock_c : Natural := 72_000_000;

	--Internal IO connection
	Signal con_gpio_o : Std_ulogic_vector(3 Downto 0);

	--PLL and clocking
	Signal clk_sys : Std_logic; --72 MHz system clock from PLL
	Signal pll_locked : Std_logic;
	Signal rstn_sync : Std_logic;

	--Camera XCLK signal (internal, before output)
	Signal xclk_int : Std_ulogic;

	--Camera signal activity monitors
	--These counters increment when their respective signals toggle
	Signal xclk_toggle_count : unsigned(23 Downto 0) := (Others => '0');
	Signal pclk_toggle_count : unsigned(23 Downto 0) := (Others => '0');
	Signal vsync_toggle_count : unsigned(23 Downto 0) := (Others => '0');
	Signal href_toggle_count : unsigned(23 Downto 0) := (Others => '0');
	Signal ov_rst_toggle_count : unsigned(23 Downto 0) := (Others => '0');
	Signal pd_toggle_count : unsigned(23 Downto 0) := (Others => '0');
	--Previous state registers for edge detection (sampled in clk_sys domain)
	Signal xclk_prev : Std_ulogic := '0';
	Signal xclk_sync : Std_ulogic := '0';
	Signal pclk_prev : Std_ulogic := '0';
	Signal pclk_sync : Std_ulogic := '0';
	Signal vsync_prev : Std_ulogic := '0';
	Signal vsync_sync : Std_ulogic := '0';
	Signal href_prev : Std_ulogic := '0';
	Signal href_sync : Std_ulogic := '0';
	Signal ov_rst_prev : Std_ulogic := '0';
	Signal ov_rst_sync : Std_ulogic := '0';
	Signal pd_prev : Std_ulogic := '0';
	Signal pd_sync : Std_ulogic := '0';

Begin

	--PLL instantiation: generates 72 MHz system clock and 24 MHz camera clock
	pll_24_72_inst : Entity work.pll_12_to_24_72
		Port Map(
			pll_12_to_24_72_module_CLKI  => ECP5EVN_CLK, --12 MHz input
			pll_12_to_24_72_module_CLKOP => clk_sys, --72 MHz system clock
			pll_12_to_24_72_module_CLKOS => xclk_int, --24 MHz camera clock
			pll_12_to_24_72_module_LOCK  => pll_locked
		);

	--Output XCLK to camera
	XCLK <= xclk_int;

	--Combine external reset with PLL lock
	rstn_sync <= ECP5EVN_RST_N And pll_locked;

	--Drive LEDs with MSB of toggle counters
	--ECP5EVN_LED0 <= xclk_toggle_count(23);   
	--ECP5EVN_LED1 <= pclk_toggle_count(23);   
	--ECP5EVN_LED2 <= vsync_toggle_count(23);  
	--ECP5EVN_LED3 <= href_toggle_count(23);   
	--ECP5EVN_LED4 <= ov_rst_toggle_count(23);
	--ECP5EVN_LED4 <= OV5640_RESET;
	--ECP5EVN_LED5 <= pd_toggle_count(23);
	--ECP5EVN_LED5 <= POWER_DOWN;

	ECP5EVN_LED0 <= Data(0);
	ECP5EVN_LED1 <= Data(1);
	ECP5EVN_LED2 <= Data(2);
	ECP5EVN_LED3 <= Data(3);
	ECP5EVN_LED4 <= Data(4);
	ECP5EVN_LED5 <= Data(5);
	ECP5EVN_LED6 <= Data(6);
	ECP5EVN_LED7 <= Data(7);

	neorv32_inst : Entity neorv32.neorv32_ProcessorTop_MinimalBoot
		Generic Map(
			CLOCK_FREQUENCY => f_clock_c, --72 MHz system clock
			IMEM_SIZE       => 128 * 1024, --128 KB instruction memory
			DMEM_SIZE       => 128 * 1024 --128 KB data memory
		)
		Port Map(
			--Global control
			clk_i        => Std_ulogic(clk_sys),
			rstn_i       => Std_ulogic(rstn_sync),

			--Primary UART0
			uart_txd_o   => ECP5EVN_TX, --UART0 send data
			uart_rxd_i   => ECP5EVN_RX, --UART0 receive data

			--Camera interface (passed through to wb_ov5640 peripheral)
			SIO_C        => SIO_C,
			SIO_D        => SIO_D,
			VSYNC        => VSYNC,
			HREF         => HREF,
			PCLK         => PCLK,
			Data         => Data,
			OV5640_RESET => OV5640_RESET,
			POWER_DOWN   => POWER_DOWN
		);

End Architecture;
