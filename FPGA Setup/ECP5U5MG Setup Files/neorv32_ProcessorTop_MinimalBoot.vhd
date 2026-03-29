-- ================================================================================ --
-- NEORV32 Templates - Minimal generic setup with the bootloader enabled --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32 --
-- Copyright (c) NEORV32 contributors. --
-- Copyright (c) 2020 - 2025 Stephan Nolting. All rights reserved. --
-- Licensed under the BSD-3-Clause license, see LICENSE for details. --
-- SPDX-License-Identifier: BSD-3-Clause --
-- ================================================================================ --

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY neorv32;
USE neorv32.neorv32_package.ALL;
ENTITY neorv32_ProcessorTop_MinimalBoot IS
	GENERIC (
		-- Clocking --
		CLOCK_FREQUENCY : NATURAL := 0; -- clock frequency of clk_i in Hz
		-- Internal Instruction memory --
		IMEM_EN   : BOOLEAN := true; -- implement processor-internal instruction memory
		IMEM_SIZE : NATURAL := 64 * 1024; -- size of processor-internal instruction memory in bytes
		-- Internal Data memory --
		DMEM_EN   : BOOLEAN := true; -- implement processor-internal data memory
		DMEM_SIZE : NATURAL := 64 * 1024 -- size of processor-internal data memory in bytes
		-- Processor peripherals --
		--IO_GPIO_NUM : natural := 4; -- number of GPIO input/output pairs (0..32)
		--IO_PWM_NUM_CH : natural := 3 -- number of PWM channels to implement (0..16)
	);
	PORT (
		-- Global control --
		clk_i  : IN std_logic;
		rstn_i : IN std_logic;
		-- GPIO (available if IO_GPIO_EN = true) --
		--gpio_o : out std_ulogic_vector(IO_GPIO_NUM-1 downto 0);
		-- primary UART0 (available if IO_UART0_EN = true) --
		uart_txd_o : OUT std_ulogic; -- UART0 send data
		uart_rxd_i : IN std_ulogic := '0'; -- UART0 receive data
		-- PWM (available if IO_PWM_NUM_CH > 0) --
		--pwm_o : out std_ulogic_vector(IO_PWM_NUM_CH-1 downto 0)
		--Interface for the camera harware
		SIO_C        : INOUT Std_ulogic; --SIO_C - SCCB clock signal. FPGA -> Camera
		SIO_D        : INOUT Std_ulogic; --SIO_D - SCCB data signal (bi-direcctional). FPGA <--> Camera
		VSYNC        : IN Std_ulogic; --Camera VSYNC signal
		HREF         : IN Std_ulogic; --Camera HREF signal
		PCLK         : IN Std_ulogic; --Camera PCLK signal
		Data         : IN Std_ulogic_vector (7 DOWNTO 0); --Camera data out pins
		OV5640_RESET : OUT Std_ulogic; --Camera reset
		POWER_DOWN   : OUT Std_ulogic --Camera power down
	);
END ENTITY;

ARCHITECTURE neorv32_ProcessorTop_MinimalBoot_rtl OF neorv32_ProcessorTop_MinimalBoot IS

	-- internal IO connection --
	SIGNAL con_gpio_o    : std_ulogic_vector(31 DOWNTO 0);
	SIGNAL con_pwm_o     : std_ulogic_vector(15 DOWNTO 0);

	SIGNAL rstn_internal : std_ulogic; --internal signal to invert the reset signal
	--Interconnect component
	COMPONENT wb_1m2s_interconnect IS
		PORT (
			clk   : IN Std_ulogic; --system clock
			reset : IN Std_ulogic; --synchronous reset
			--Master pins
			m_i_wb_cyc   : IN Std_ulogic; --Master Wishbone: cycle valid
			m_i_wb_stb   : IN Std_ulogic; --Master Wishbone: strobe
			m_i_wb_we    : IN Std_ulogic; --Master Wishbone: 1=write, 0=read
			m_i_wb_addr  : IN Std_ulogic_vector(31 DOWNTO 0);--Master Wishbone: address
			m_i_wb_data  : IN Std_ulogic_vector(31 DOWNTO 0);--Master Wishbone: write data
			m_o_wb_ack   : OUT Std_ulogic; --Master Wishbone: acknowledge
			m_o_wb_stall : OUT Std_ulogic; --Master Wishbone: stall (always '0')
			m_o_wb_data  : OUT Std_ulogic_vector(31 DOWNTO 0); --Master Wishbone: read data

			--S0 pins. Peripheral pin directions are inverted compared to master
			s0_o_wb_cyc   : OUT Std_ulogic; --S0 Wishbone: cycle valid
			s0_o_wb_stb   : OUT Std_ulogic; --S0 Wishbone: strobe
			s0_o_wb_we    : OUT Std_ulogic; --S0 Wishbone: 1=write, 0=read
			s0_o_wb_addr  : OUT Std_ulogic_vector(31 DOWNTO 0);--S0 Wishbone: address
			s0_o_wb_data  : OUT Std_ulogic_vector(31 DOWNTO 0);--S0 Wishbone: write data
			s0_i_wb_ack   : IN Std_ulogic; --S0 Wishbone: acknowledge
			s0_i_wb_stall : IN Std_ulogic; --S0 Wishbone: stall (always '0')
			s0_i_wb_data  : IN Std_ulogic_vector(31 DOWNTO 0); --S0 Wishbone: read data

			--S1 pins
			s1_o_wb_cyc   : OUT Std_ulogic; --S1 Wishbone: cycle valid
			s1_o_wb_stb   : OUT Std_ulogic; --S1 Wishbone: strobe
			s1_o_wb_we    : OUT Std_ulogic; --S1 Wishbone: 1=write, 0=read
			s1_o_wb_addr  : OUT Std_ulogic_vector(31 DOWNTO 0);--S1 Wishbone: address
			s1_o_wb_data  : OUT Std_ulogic_vector(31 DOWNTO 0);--S1 Wishbone: write data
			s1_i_wb_ack   : IN Std_ulogic; --S1 Wishbone: acknowledge
			s1_i_wb_stall : IN Std_ulogic; --S1 Wishbone: stall (always '0')
			s1_i_wb_data  : IN Std_ulogic_vector(31 DOWNTO 0) --S1 Wishbone: read data
		);
	END COMPONENT;

	--NPU declaration
	COMPONENT wb_peripheral_top
		GENERIC (
			BASE_ADDRESS : std_ulogic_vector(31 DOWNTO 0) := x"90000000"
		);
		PORT (
			clk        : IN std_ulogic;
			reset      : IN std_ulogic;
			i_wb_cyc   : IN std_ulogic;
			i_wb_stb   : IN std_ulogic;
			i_wb_we    : IN std_ulogic;
			i_wb_addr  : IN std_ulogic_vector(31 DOWNTO 0);
			i_wb_data  : IN std_ulogic_vector(31 DOWNTO 0);
			o_wb_ack   : OUT std_ulogic;
			o_wb_stall : OUT std_ulogic;
			o_wb_data  : OUT std_ulogic_vector(31 DOWNTO 0)
		);
	END COMPONENT;

	--Camera component
	COMPONENT wb_ov5640 IS
		GENERIC (
			BASE_ADDRESS                 : Std_ulogic_vector(31 DOWNTO 0) := x"90010000"; --peripheral base (informational)
			CAMERA_CONTROL_ADDRESS       : Std_ulogic_vector(31 DOWNTO 0) := x"90010000"; --Camera control register. [0] = enable, [1] = reset
			CAMERA_STATUS_ADDRESS        : Std_ulogic_vector(31 DOWNTO 0) := x"90010004"; --Camera status register. [0]=busy, [1]=done (sticky)
			IMAGE_FORMAT_ADDRESS         : Std_ulogic_vector(31 DOWNTO 0) := x"90010008"; --Image format. [0] = 1 for YUV422. (Lowest3 bits can be used to select the format)
			IMAGE_RESOLUTION_ADDRESS     : Std_ulogic_vector(31 DOWNTO 0) := x"9001000C"; --[15:0] = image width. [31:16] = image height
			MASTER_WORDS_TO_READ_ADDRESS : Std_ulogic_vector(31 DOWNTO 0) := x"90010010"; --32-bit words the master has to read to gather the complete image
			IMAGE_BUFFER_BASE            : Std_ulogic_vector(31 DOWNTO 0) := x"90011000" --Image buffer base address
		);
		PORT (
			clk        : IN Std_ulogic; --system clock
			reset      : IN Std_ulogic; --synchronous reset
			i_wb_cyc   : IN Std_ulogic; --Wishbone: cycle valid
			i_wb_stb   : IN Std_ulogic; --Wishbone: strobe
			i_wb_we    : IN Std_ulogic; --Wishbone: 1=write, 0=read
			i_wb_addr  : IN Std_ulogic_vector(31 DOWNTO 0);--Wishbone: address
			i_wb_data  : IN Std_ulogic_vector(31 DOWNTO 0);--Wishbone: write data
			o_wb_ack   : OUT Std_ulogic; --Wishbone: acknowledge
			o_wb_stall : OUT Std_ulogic; --Wishbone: stall (always '0')
			o_wb_data  : OUT Std_ulogic_vector(31 DOWNTO 0); --Wishbone: read data
			--Interface for the camera harware
			SIO_C        : INOUT Std_ulogic; --SIO_C - SCCB clock signal. FPGA -> Camera
			SIO_D        : INOUT Std_ulogic; --SIO_D - SCCB data signal (bi-direcctional). FPGA <--> Camera
			VSYNC        : IN Std_ulogic; --Camera VSYNC signal
			HREF         : IN Std_ulogic; --Camera HREF signal
			PCLK         : IN Std_ulogic; --Camera PCLK signal
			Data         : IN Std_ulogic_vector (7 DOWNTO 0); --Camera data out pins
			OV5640_RESET : OUT Std_ulogic; --Camera reset
			POWER_DOWN   : OUT Std_ulogic --Camera power down

		);
	END COMPONENT;
	-- External bus interface (available if XBUS_EN = true) --
	--Now connected to the interconnect
	SIGNAL xbus_adr_o : std_ulogic_vector(31 DOWNTO 0); -- address
	SIGNAL xbus_dat_o : std_ulogic_vector(31 DOWNTO 0); -- write data
	SIGNAL xbus_cti_o : std_ulogic_vector(2 DOWNTO 0); -- cycle type
	SIGNAL xbus_tag_o : std_ulogic_vector(2 DOWNTO 0); -- access tag
	SIGNAL xbus_we_o  : std_ulogic; -- read/write
	SIGNAL xbus_sel_o : std_ulogic_vector(3 DOWNTO 0); -- byte enable
	SIGNAL xbus_stb_o : std_ulogic; -- strobe
	SIGNAL xbus_cyc_o : std_ulogic; -- valid cycle
	SIGNAL xbus_dat_i : std_ulogic_vector(31 DOWNTO 0) := (OTHERS => 'L'); -- read data
	SIGNAL xbus_ack_i : std_ulogic := 'L'; -- transfer acknowledge
	SIGNAL xbus_err_i : std_ulogic := 'L'; -- transfer error

	--Slave 0 Wishbone signals
	SIGNAL s0_o_wb_cyc   : Std_ulogic; --S0 Wishbone: cycle valid
	SIGNAL s0_o_wb_stb   : Std_ulogic; --S0 Wishbone: strobe
	SIGNAL s0_o_wb_we    : Std_ulogic; --S0 Wishbone: 1=write, 0=read
	SIGNAL s0_o_wb_addr  : Std_ulogic_vector(31 DOWNTO 0);--S0 Wishbone: address
	SIGNAL s0_o_wb_data  : Std_ulogic_vector(31 DOWNTO 0);--S0 Wishbone: write data
	SIGNAL s0_i_wb_ack   : Std_ulogic; --S0 Wishbone: acknowledge
	SIGNAL s0_i_wb_stall : Std_ulogic; --S0 Wishbone: stall (always '0')
	SIGNAL s0_i_wb_data  : Std_ulogic_vector(31 DOWNTO 0); --S0 Wishbone: read data
	--Slave 1 Wishbone signals
	SIGNAL s1_o_wb_cyc   : Std_ulogic; --S1 Wishbone: cycle valid
	SIGNAL s1_o_wb_stb   : Std_ulogic; --S1 Wishbone: strobe
	SIGNAL s1_o_wb_we    : Std_ulogic; --S1 Wishbone: 1=write, 0=read
	SIGNAL s1_o_wb_addr  : Std_ulogic_vector(31 DOWNTO 0);--S1 Wishbone: address
	SIGNAL s1_o_wb_data  : Std_ulogic_vector(31 DOWNTO 0);--S1 Wishbone: write data
	SIGNAL s1_i_wb_ack   : Std_ulogic; --S1 Wishbone: acknowledge
	SIGNAL s1_i_wb_stall : Std_ulogic; --S1 Wishbone: stall (always '0')
	SIGNAL s1_i_wb_data  : Std_ulogic_vector(31 DOWNTO 0); --S1 Wishbone: read data

BEGIN
	rstn_internal <= NOT(rstn_i);
	-- The core of the problem ----------------------------------------------------------------
	-- -------------------------------------------------------------------------------------------
	neorv32_inst : ENTITY neorv32.neorv32_top
			GENERIC MAP(
			-- Clocking --
			CLOCK_FREQUENCY => CLOCK_FREQUENCY, -- clock frequency of clk_i in Hz
			-- Boot Configuration --
			BOOT_MODE_SELECT => 0, -- boot via internal bootloader
			-- RISC-V CPU Extensions --
			RISCV_ISA_Zicntr => true, -- implement base counters?
			RISCV_ISA_M      => true, -- implement mul/div extension?
			RISCV_ISA_C      => true, -- implement compressed extension?
			-- Internal Instruction memory --
			IMEM_EN   => true, -- implement processor-internal instruction memory
			IMEM_SIZE => IMEM_SIZE, -- size of processor-internal instruction memory in bytes
			-- Internal Data memory --
			DMEM_EN   => true, -- implement processor-internal data memory
			DMEM_SIZE => DMEM_SIZE, -- size of processor-internal data memory in bytes
			-- Processor peripherals --
			--IO_GPIO_NUM => IO_GPIO_NUM, -- number of GPIO input/output pairs (0..32)
			IO_CLINT_EN => true, -- implement core local interruptor (CLINT)?
			IO_UART0_EN => true, -- implement primary universal asynchronous receiver/transmitter (UART0)?
			--IO_PWM_NUM_CH => IO_PWM_NUM_CH, -- number of PWM channels to implement (0..12); 0 = disabled
			XBUS_EN      => true, 
			XBUS_TIMEOUT => 20
			)
			PORT MAP(
				-- Global control --
				clk_i  => clk_i, -- global clock, rising edge
				rstn_i => rstn_i, -- global reset, low-active, async
				-- GPIO (available if IO_GPIO_NUM > 0) --
				--gpio_o => con_gpio_o, -- parallel output
				--gpio_i => (others => '0'), -- parallel input
				-- primary UART0 (available if IO_UART0_EN = true) --
				uart0_txd_o => uart_txd_o, -- UART0 send data
				uart0_rxd_i => uart_rxd_i, -- UART0 receive data
				-- PWM (available if IO_PWM_NUM_CH > 0) --
				--pwm_o => con_pwm_o, -- pwm channels
				xbus_adr_o => xbus_adr_o, -- address
				xbus_dat_o => xbus_dat_o, -- write data
				xbus_cti_o => xbus_cti_o, -- cycle type
				xbus_tag_o => xbus_tag_o, -- access tag
				xbus_we_o  => xbus_we_o, -- read/write
				xbus_sel_o => xbus_sel_o, -- byte enable
				xbus_stb_o => xbus_stb_o, -- strobe
				xbus_cyc_o => xbus_cyc_o, -- valid cycle
				xbus_dat_i => xbus_dat_i, -- read data
				xbus_ack_i => xbus_ack_i, -- transfer acknowledge
				xbus_err_i => xbus_err_i -- transfer error
			);

				wb_1m2s_interconnect_inst : wb_1m2s_interconnect
				PORT MAP(
					clk   => clk_i, 
					reset => rstn_internal, 
					--Master pins
					m_i_wb_cyc   => xbus_cyc_o, 
					m_i_wb_stb   => xbus_stb_o, 
					m_i_wb_we    => xbus_we_o, 
					m_i_wb_addr  => xbus_adr_o, 
					m_i_wb_data  => xbus_dat_o, 
					m_o_wb_ack   => xbus_ack_i, 
					m_o_wb_stall => OPEN, 
					m_o_wb_data  => xbus_dat_i, 

					--S0 pins. Peripheral pin directions are inverted compared to master
					s0_o_wb_cyc   => s0_o_wb_cyc, 
					s0_o_wb_stb   => s0_o_wb_stb, 
					s0_o_wb_we    => s0_o_wb_we, 
					s0_o_wb_addr  => s0_o_wb_addr, 
					s0_o_wb_data  => s0_o_wb_data, 
					s0_i_wb_ack   => s0_i_wb_ack, 
					s0_i_wb_stall => s0_i_wb_stall, 
					s0_i_wb_data  => s0_i_wb_data, 

					--S1 pins
					s1_o_wb_cyc   => s1_o_wb_cyc, 
					s1_o_wb_stb   => s1_o_wb_stb, 
					s1_o_wb_we    => s1_o_wb_we, 
					s1_o_wb_addr  => s1_o_wb_addr, 
					s1_o_wb_data  => s1_o_wb_data, 
					s1_i_wb_ack   => s1_i_wb_ack, 
					s1_i_wb_stall => s1_i_wb_stall, 
					s1_i_wb_data  => s1_i_wb_data
		);

					wb_peripheral_top_inst : wb_peripheral_top
						GENERIC MAP(
						BASE_ADDRESS => x"90000000"
						)
						PORT MAP(
							clk        => clk_i, 
							reset      => rstn_internal, 
							i_wb_cyc   => s0_o_wb_cyc, 
							i_wb_stb   => s0_o_wb_stb, 
							i_wb_we    => s0_o_wb_we, 
							i_wb_addr  => s0_o_wb_addr, 
							i_wb_data  => s0_o_wb_data, 
							o_wb_ack   => s0_i_wb_ack, 
							o_wb_stall => s0_i_wb_stall, 
							o_wb_data  => s0_i_wb_data
							--buttons => buttons,
							--leds => leds
						);
							xbus_err_i <= '0';

							wb_ov5640_inst : wb_ov5640
							PORT MAP(
								clk          => clk_i, 
								reset        => rstn_internal, 
								i_wb_cyc     => s1_o_wb_cyc, 
								i_wb_stb     => s1_o_wb_stb, 
								i_wb_we      => s1_o_wb_we, 
								i_wb_addr    => s1_o_wb_addr, 
								i_wb_data    => s1_o_wb_data, 
								o_wb_ack     => s1_i_wb_ack, 
								o_wb_stall   => s1_i_wb_stall, 
								o_wb_data    => s1_i_wb_data, 
								SIO_C        => SIO_C, 
								SIO_D        => SIO_D, 
								VSYNC        => VSYNC, 
								HREF         => HREF, 
								PCLK         => PCLK, 
								Data         => Data, 
								OV5640_RESET => OV5640_RESET, 
								POWER_DOWN   => POWER_DOWN
	);

								-- GPIO --
								--gpio_o <= con_gpio_o(IO_GPIO_NUM-1 downto 0);

								-- PWM --
								--pwm_o <= con_pwm_o(IO_PWM_NUM_CH-1 downto 0);

END ARCHITECTURE;
