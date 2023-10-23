library IEEE;
use ieee.std_logic_1164.all; 
use ieee.numeric_std.ALL;
use ieee.std_logic_unsigned.all; 
use work.CustomDataTypes.all;
use work.AXI_Bus_Package.all;

--
-- Example top-level module for parsing simple AXI instructions
--
entity topmod is
    port (
        sysClk          :   in  std_logic;
        aresetn         :   in  std_logic;
        ext_i           :   in  std_logic_vector(7 downto 0);

        addr_i          :   in  unsigned(AXI_ADDR_WIDTH-1 downto 0);            --Address out
        writeData_i     :   in  std_logic_vector(AXI_DATA_WIDTH-1 downto 0);    --Data to write
        dataValid_i     :   in  std_logic_vector(1 downto 0);                   --Data valid out signal
        readData_o      :   out std_logic_vector(AXI_DATA_WIDTH-1 downto 0);    --Data to read
        resp_o          :   out std_logic_vector(1 downto 0);                   --Response in
        
        ext_o           :   out std_logic_vector(7 downto 0);
        led_o           :   out std_logic_vector(7 downto 0);
        
        adcClk          :   in  std_logic;
        adcData_i       :   in  std_logic_vector(31 downto 0);
        
        m_axis_tdata    :   out std_logic_vector(31 downto 0);
        m_axis_tvalid   :   out std_logic
    );
end topmod;


architecture Behavioural of topmod is

ATTRIBUTE X_INTERFACE_INFO : STRING;
ATTRIBUTE X_INTERFACE_INFO of m_axis_tdata: SIGNAL is "xilinx.com:interface:axis:1.0 m_axis TDATA";
ATTRIBUTE X_INTERFACE_INFO of m_axis_tvalid: SIGNAL is "xilinx.com:interface:axis:1.0 m_axis TVALID";
ATTRIBUTE X_INTERFACE_PARAMETER : STRING;
ATTRIBUTE X_INTERFACE_PARAMETER of m_axis_tdata: SIGNAL is "CLK_DOMAIN system_processing_system7_0_0_FCLK_CLK0,FREQ_HZ 125000000";
ATTRIBUTE X_INTERFACE_PARAMETER of m_axis_tvalid: SIGNAL is "CLK_DOMAIN system_processing_system7_0_0_FCLK_CLK0,FREQ_HZ 125000000";

COMPONENT BlockMemory
  PORT (
    clka : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    douta : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
  );
END COMPONENT;

COMPONENT DDS1
  PORT (
    aclk : IN STD_LOGIC;
    aresetn : IN STD_LOGIC;
    s_axis_phase_tvalid : IN STD_LOGIC;
    s_axis_phase_tdata : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    m_axis_data_tvalid : OUT STD_LOGIC;
    m_axis_data_tdata : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
  );
END COMPONENT;

--
-- AXI communication signals
--
signal comState             :   t_status                        :=  idle;
signal bus_m                :   t_axi_bus_master                :=  INIT_AXI_BUS_MASTER;
signal bus_s                :   t_axi_bus_slave                 :=  INIT_AXI_BUS_SLAVE;
signal reset                :   std_logic;
--
-- Registers
--
signal triggers             :   t_param_reg                     :=  (others => '0');
signal outputReg            :   t_param_reg                     :=  (others => '0');
signal dac_o                :   t_param_reg;
signal dds_phase_inc_reg    :   t_param_reg;
signal dds_phase_off_reg    :   t_param_reg;
--
-- DDS signals
--
signal phase_offset         :   std_logic_vector(31 downto 0);
signal phase_inc            :   std_logic_vector(31 downto 0);
signal dds_phase_i          :   std_logic_vector(63 downto 0);
signal dds_o                :   std_logic_vector(31 downto 0);
signal dds_cos, dds_sin     :   std_logic_vector(9 downto 0);
--
-- Block memory signals
--
signal wea          :   std_logic_vector(0 downto 0);
signal addra        :   std_logic_vector(7 downto 0);
signal dina, douta  :   std_logic_vector(31 downto 0);
signal memDelay     :   unsigned(1 downto 0);

begin

--
-- DAC Outputs
--
m_axis_tdata <= dac_o;
m_axis_tvalid <= '1';
--
-- Digital outputs
--
ext_o <= outputReg(7 downto 0);
led_o <= outputReg(15 downto 8);
--
-- Signal assignement
--


--
-- Block memory
--
BM : BlockMemory
PORT MAP (
    clka    => sysClk,
    wea     => wea,
    addra   => addra,
    dina    => dina,
    douta   => douta
);
--
-- DDS
--
DDS_inst : DDS1
  PORT MAP (
    aclk                    => adcClk,
    aresetn                 => aresetn,
    s_axis_phase_tvalid     => '1',
    s_axis_phase_tdata      => dds_phase_i,
    m_axis_data_tvalid      => open,
    m_axis_data_tdata       => dds_o
  );
  
phase_inc <= dds_phase_inc_reg;
phase_offset <= dds_phase_off_reg;
dds_phase_i <= phase_offset & phase_inc;
dds_cos <= dds_o(9 downto 0);
dds_sin <= dds_o(25 downto 16);

dac_o(15 downto 0) <= std_logic_vector(shift_left(resize(signed(dds_cos),16),4));
dac_o(31 downto 16) <= std_logic_vector(shift_left(resize(signed(dds_sin),16),4));

--
-- AXI communication routing - connects bus objects to std_logic signals
--
bus_m.addr <= addr_i;
bus_m.valid <= dataValid_i;
bus_m.data <= writeData_i;
readData_o <= bus_s.data;
resp_o <= bus_s.resp;

Parse: process(sysClk,aresetn) is
begin
    if aresetn = '0' then
        comState <= idle;
        reset <= '0';
        bus_s <= INIT_AXI_BUS_SLAVE;
        triggers <= (others => '0');
        outputReg <= (others => '0');
        dds_phase_off_reg <= (others => '0');
        dds_phase_inc_reg <= std_logic_vector(to_unsigned(34359738,32));    --1 MHz with 32 bit DDS width and 125 MHz clock frequency
        addra <= (others => '0');
        dina <= (others => '0');
        memDelay <= (others => '0');
        wea <= "0";
    elsif rising_edge(sysClk) then
        FSM: case(comState) is
            when idle =>
                triggers <= (others => '0');
                reset <= '0';
                bus_s.resp <= "00";
                memDelay <= "00";
                if bus_m.valid(0) = '1' then
                    comState <= processing;
                end if;

            when processing =>
                AddrCase: case(bus_m.addr(31 downto 24)) is
                    --
                    -- Parameter parsing
                    --
                    when X"00" =>
                        ParamCase: case(bus_m.addr(23 downto 0)) is
                            when X"000000" => rw(bus_m,bus_s,comState,triggers);
                            when X"000004" => rw(bus_m,bus_s,comState,outputReg);
--                            when X"000008" => rw(bus_m,bus_s,comState,dac_o);
                            when X"00000C" => readOnly(bus_m,bus_s,comState,adcData_i);
                            when X"000010" => readOnly(bus_m,bus_s,comState,ext_i);
                            when X"000014" => rw(bus_m,bus_s,comState,dds_phase_inc_reg);
                            when X"000018" => rw(bus_m,bus_s,comState,dds_phase_off_reg);
                            
                            when others => 
                                comState <= finishing;
                                bus_s.resp <= "11";
                        end case;
                        
                    --
                    -- Read from/write to memory
                    --
                    when X"01" =>
                        addra <= std_logic_vector(bus_m.addr(addra'length + 1 downto 2));
                        if bus_m.valid(1) = '0' then
                            --
                            -- If writing data, route input address and data to memory
                            --
                            comState <= finishing;
                            dina <= bus_m.data;
                            wea <= "1";
                            bus_s.resp <= "01";
                        else
                            --
                            -- If reading from memory, we need an extra 2 wait cycles
                            --
                            if memDelay = "00" then
                                memDelay <= "11";
                            elsif memDelay > "01" then
                                memDelay <= memDelay - 1;
                            else
                                bus_s.data <= douta;
                                bus_s.resp <= "01";
                                comState <= finishing;
                            end if;
                        end if;
                    
                    when others => 
                        comState <= finishing;
                        bus_s.resp <= "11";
                end case;
            when finishing =>
                wea <= "0";
                comState <= idle;

            when others => comState <= idle;
        end case;
    end if;
end process;

    
end architecture Behavioural;