# Wishbone Interconnect – 1 Master, 2 Slaves

A simple Wishbone interconnect that connects **one master** to **two slaves** using address-based slave selection.

This project was created to connect an NPU (https://github.com/dipenarathod/Wishbone-NPU/tree/main) and an OV5640 Camera Controller (https://github.com/dipenarathod/Wishbone-Camera-Controller-for-OV5640) to the XBUS interface of a NEORV32 (https://github.com/stnolting/neorv32)

## Overview

This interconnect accepts Wishbone requests from a single master and routes them to one of two slave interfaces based on the incoming address.

The design:
- Decodes the master address against two configurable base regions
- Latches the selected slave and request fields during an active transaction
- Drives only the selected slave's `cyc` and `stb` signals
- Returns read data, acknowledge, and stall from the selected slave back to the master

## Entity

**Entity name:** `wb_1m2s_interconnect`

### Generics

| Generic | Width | Default | Description |
|--------|------:|---------|-------------|
| `S0_BASE` | 32 | `x"9000_0000"` | Base address for slave 0 |
| `S1_BASE` | 32 | `x"9001_0000"` | Base address for slave 1 |
| `S_MASK`  | 32 | `x"FFFF_0000"` | Address mask used for slave selection |

### Master interface

| Signal | Dir | Width | Description |
|--------|-----|------:|-------------|
| `clk` | In | 1 | System clock |
| `reset` | In | 1 | Synchronous reset |
| `m_i_wb_cyc` | In | 1 | Wishbone cycle valid |
| `m_i_wb_stb` | In | 1 | Wishbone strobe |
| `m_i_wb_we` | In | 1 | Write enable (`1` = write, `0` = read) |
| `m_i_wb_addr` | In | 32 | Address from master |
| `m_i_wb_data` | In | 32 | Write data from master |
| `m_o_wb_ack` | Out | 1 | Acknowledge to master |
| `m_o_wb_stall` | Out | 1 | Stall to master |
| `m_o_wb_data` | Out | 32 | Read data to master |

### Slave interfaces

Each slave uses the same Wishbone-style signal group:
- Output to slave: `*_o_wb_cyc`, `*_o_wb_stb`, `*_o_wb_we`, `*_o_wb_addr`, `*_o_wb_data`
- Input from slave: `*_i_wb_ack`, `*_i_wb_stall`, `*_i_wb_data`

The two slave ports are:
- `s0_*` for slave 0
- `s1_*` for slave 1

## Address decoding

The interconnect selects a slave using masked address comparison:

- Slave 0 is selected when `(m_i_wb_addr AND S_MASK) = S0_BASE`
- Slave 1 is selected when `(m_i_wb_addr AND S_MASK) = S1_BASE`
- If neither comparison matches, no slave is selected

With the default generic values:
- Slave 0 region: `0x9000_0000` to `0x9000_FFFF`
- Slave 1 region: `0x9001_0000` to `0x9001_FFFF`

## Internal behavior

The design uses:
- `slave_select` for combinational decode
- `slave_select_lat` for the latched active-slave selection
- `m_addr_lat`, `m_data_lat`, and `m_we_lat` to hold request fields stable during a transaction
- `stb_lat` to keep the selected transfer active until completion

A transaction begins when both `m_i_wb_cyc` and `m_i_wb_stb` are asserted.

When a transaction starts, and no slave is currently active, the interconnect latches:
- The decoded slave
- The incoming address
- The write data
- The write-enable bit

The transaction ends when:
- Slave 0 acknowledges while selected, or
- Slave 1 acknowledges while selected, or
- The master drops `m_i_wb_cyc`

## Return path

The master return signals depend on the currently latched slave:

- If slave 0 is active, the master receives `s0_i_wb_data`, `s0_i_wb_ack`, and `s0_i_wb_stall`
- If slave 1 is active, the master receives `s1_i_wb_data`, `s1_i_wb_ack`, and `s1_i_wb_stall`
- If no slave is active, the master gets zero data, zero acknowledge, and zero stall

## File

- [RTL](RTL) — VHDL source for the interconnect

## Example use case

A typical mapping could look like:
- `0x9000_xxxx` -> Slave 0
- `0x9001_xxxx` -> Slave 1

## Notes

- The reset is synchronous.
- The design uses VHDL 2008 with `process(all)` style combinational logic.
- Request fields are latched so the selected slave sees stable address, data, and write control until acknowledged.
- `cyc` and `stb` are only asserted toward the selected slave.

## Related Repositories
- **[Wishbone NPU](https://github.com/dipenarathod/Wishbone-NPU)** - Wishbone Peripheral used to interface the Waveshare OV5640 Camera (Version C) with the NEORV32
- **[Wishbone Interconnect 1 Master 2 Slaves](https://github.com/dipenarathod/Wishbone-Interconnect-1-Master-2-Slaves)** - Wishbone Interconnect to connect 2 Wishbone Peripherals to a Master. Video in the repository shows how to connect the NEORV32 (controller) to the camera controller and the NPU (2 slaves)

## Video Guides
- **[TODO: Add video for interconnect]**
- **[Connecting the Wishbone Camera Controller to the NEORV32](https://www.youtube.com/playlist?list=PLTuulhiizN0K-HTymHKr1Nurv-iq_RdWK)** - Shows you how to connect the NEORV32 to a Wishbone Camera Controller for OV5640
- **[Video Playlist showing how to connect the NPU to the NEORV32 in Lattice Diamond](https://www.youtube.com/playlist?list=PLTuulhiizN0IWdHwq5sg6dwhZwYaWbUX5)** - Refer to Parts 1 and 3 of this playlist to learn how to create a Diamond Project using a TCL Script and how to increase the IMEM and DMEM sizes of the NEORV32

