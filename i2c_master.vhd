--=============================================================================
-- Module Name : i2c_master
-- Library     : 
-- Project     : V3718
-- Company     : CAEN SpA
-- Author      : A.Potenza
-------------------------------------------------------------------------------
--  Description: 
--------------------------------------------------------------------
-- (c) Copyright 2020 CAEN SpA. Via Vetraia 11, Viareggio
-- (Lucca), 55049, Italy. <www.caen.it>. All rights reserved.
-- THIS COPYRIGHT NOTICE MUST BE RETAINED AS PART OF THIS FILE AT ALL TIMES.
-------------------------------------------------------------------------------
-- Revision History:
-- Date        Version  Author         Description
-- 23/10/2019  1.0.0    APO            Initial release
--=============================================================================
-- TODO
-- ------
--
-- - Remove buffer instances
-- - Clock stretching
-- - Back with EM2130 readout

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

entity i2c_master is
  generic (
    CC_HALFP : integer := 20 -- Clock Cycle Half Period
  );
  port (
    resetn    : in std_logic;                      -- Reset active high
    clk       : in std_logic;                      -- input clock
    nbyte     : in std_logic_vector(5 downto 0);   -- byte to transfert
    address   : in std_logic_vector(6 downto 0);   -- i2c device/register address
    nw_r      : in std_logic;                      -- write (al) or read (ah) operation
    data_in   : in std_logic_vector(31 downto 0);  -- data to the i2c device
    data_out  : out std_logic_vector(31 downto 0); -- data from the i2c device    
    rep_start : in std_logic;                      -- Request a repetive start for next access
    req_valid : in std_logic;                      -- data valid from requester
    req_ready : out std_logic;                     -- data ready to requester
    ans_valid : out std_logic;                     -- response valid from responser
    ans_ready : in std_logic;                      -- response ready to responser
    flag_ack  : in std_logic;                      -- flag acknowledge in a read cycle (some chips require not acknowledge form the master at the end of the read cycle)
    flag_err  : out std_logic;
    stri      : in std_logic;
    recover   : in std_logic;                      -- recover pulse
    scl       : out std_logic;  -- i2c clock
    sda       : inout std_logic -- i2c data
  );
end i2c_master;

architecture rtl of i2c_master is
 
  signal scli            : std_logic                     := '0';
  signal scli_d          : std_logic                     := '0';
  signal scli_dd         : std_logic                     := '0';
  signal scl_busy        : std_logic                     := '0';
  signal scl_rdy         : std_logic                     := '0';
  signal scl_dly_flg     : std_logic                     := '0';
  signal scl_dly_done    : std_logic                     := '0';
  signal scl_dly_cnt     : unsigned(15 downto 0)         := (others => '0');
  signal scl_cnt         : unsigned(15 downto 0)         := (others => '0');
  signal scl_cyc         : unsigned(5 downto 0)          := (others => '0');
  signal glitch_up       : std_logic                     := '0';
  signal glitch_up_d     : std_logic                     := '0';
  signal glitch_up_dd    : std_logic                     := '0';
  signal glitch_dw       : std_logic                     := '0';
  signal glitch_ack      : std_logic                     := '0';
  signal sdai            : std_logic                     := 'Z';
  signal sda_rdy         : std_logic                     := '0';
  signal sda_bit         : unsigned(3 downto 0)          := (others => '0');
  signal sda_word        : unsigned(3 downto 0)          := (others => '0');
  signal dly_cnt         : unsigned(15 downto 0)         := (others => '0'); 
  signal nw_ri           : std_logic                     := '0';
  signal oe_sda          : std_logic                     := '0'; 
  signal noe_sda         : std_logic                     := '0'; 
  signal sda_temp        : std_logic                     := 'Z';
  signal sda_temp_s      : std_logic                     := 'Z';
  signal flag_addr       : std_logic                     := '0';
  signal flag_succ       : std_logic                     := '0';
  signal i2c_data        : std_logic_vector(7 downto 0)  := (others => '0');  
  signal datai           : std_logic_vector(31 downto 0) := (others => '0');
  signal data_outi       : std_logic_vector(31 downto 0) := (others => '0');
  signal nbyteu          : unsigned(5 downto 0)          := (others => '0');
  signal repetitive_start: std_logic;
  signal scl_fall_detect : std_logic;
  signal scl_i           : std_logic;
  signal req_recover     : std_logic;
  signal scl_recover_busy     : std_logic;
  
  type TYPEI2C is (S0_RECOVER, S0_REC_START, S0_REC_SHIFT, S0_IDLE, S0_START, S0_SHIFT, S0_SETADD, S0_ACK, S0_END);
  signal STATE_I2C                     : TYPEI2C;

begin

  -- NBYTE unsigned
  NBYTEu <= unsigned(NBYTE);

  -- OBUFT: 3-State Output Buffer
  --        Kintex UltraScale+
  -- Xilinx HDL Language Template, version 2018.2

  OBUFT_inst : OBUFT
  generic map(
    drive      => 8,
    iostandard => "default",
    slew       => "slow")
  port map(
    O => scl,   -- 1-bit output: Buffer output (connect directly to top-level port)
    I => scl_i, -- 1-bit input: Buffer input
    T => (stri or scl_i)  -- 1-bit input: 3-state enable input
  );

  iobuf_inst : iobuf
  generic map(
    drive      => 8,
    iostandard => "default",
    slew       => "slow")
  port map(
    o  => sda_temp, -- buffer output
    io => sda,      -- buffer inout port (connect directly to top-level port)
    i  => sdai,     -- buffer input
    t  => noe_sda   -- 3-state enable input, high=input, low=output 
  );

  noe_sda <= (not oe_sda) or stri;


  -- process to set the I2C clock
  P_SEQUENCER : process (clk)
  begin
    if rising_edge(clk) then
      if (resetn = '0') then
        scli            <= '1';
        scli_d          <= '1';
        scli_dd         <= '1';
        scl_busy        <= '0';
        scl_rdy         <= '0';
        glitch_up       <= '0';
        glitch_dw       <= '0';
        glitch_ack      <= '0';
        scl_dly_flg     <= '0';
        scl_dly_done    <= '0';
        glitch_up_d     <= '0';
        glitch_up_dd    <= '0';
        scl_fall_detect <= '0';
        scl_recover_busy     <= '0'; 
        scl_dly_cnt     <= (others => '0');
        scl_cnt         <= (others => '0');
        scl_cyc         <= (others => '0');
      else

        -- pulses
        scl_dly_done <= '0';
        scli_d       <= scli;
        scli_dd      <= scli_d;
        glitch_up_d  <= glitch_up;
        glitch_up_dd <= glitch_up_d;

        if (sda_rdy = '1') then
          scl_dly_flg <= '1';
        elsif (scl_dly_cnt = to_unsigned(cc_halfp/4, scl_cnt'length)) then
          scl_dly_flg  <= '0';
          scl_dly_done <= '1';
        end if;
        
        if (scl_dly_flg = '1') then
          scl_dly_cnt <= scl_dly_cnt + 1;
        else
          scl_dly_cnt <= (others => '0');
        end if;
        
        -- start condition: a request has been done (req_valid = '1')
        if (req_valid = '1') then                         
          if (scl_busy = '0') and (scl_dly_done = '1') then 
            scli         <= '0';                            
            scl_rdy      <= '1';                            
            scl_busy     <= '1';                            
            scl_dly_done <= '0';
            scl_cnt      <= (others => '0');                
            scl_cyc      <= (others => '0');                       
          else                                              
            scl_rdy <= '0';                                 
          end if;                                           
        end if;  
        
        -- Request of a recovery cycle
        if (req_recover = '1') then                         
          if (scl_recover_busy = '0') then
            scl_rdy      <= '0';             
            scl_recover_busy  <= '1';       
            scl_dly_done <= '0';
            scl_cnt      <= (others => '0');
            scl_cyc      <= (others => '0'); 
          else                              
            scl_rdy <= '0';                 
          end if;                           
        end if;
        
        if ((scl_busy = '1') or (scl_recover_busy = '1')) then                                  
          if (scl_cnt = to_unsigned(cc_halfp, scl_cnt'length)) then 
            scli    <= not scli;                                    
            scl_cnt <= (others => '0');                             
          else                                                      
            scl_cnt <= scl_cnt + 1;                                 
          end if;                                                   
        else                                                      
          scl_cnt <= (others => '0');                               
        end if;      
        
        -- look for falling edge of scl clock
        if (scli_d = '0' and scli_dd = '1') then 
          scl_fall_detect <= '1';
        end if;
        
        -- change SDA midway netween scl edges
        if (scl_fall_detect = '1' and scl_cnt = to_unsigned(cc_halfp/2, scl_cnt'length)) then 
          glitch_dw       <= '1';
          scl_fall_detect <= '0';
        else
          glitch_dw <= '0';
        end if;                               
        
        -- look for falling edge of scl clock
        if (scli = '0' and scli_d = '1') then
          glitch_ack <= '1';
        else
          glitch_ack <= '0';
        end if;
        
        if (scli = '1' and scli_d = '0') then
          glitch_up <= '1';
        else
          glitch_up <= '0';
        end if;
        
         -- if number of cycles = 8*nbyte + nbyte (es: nbyte = 2, number of cycles = 18 = 8 + acknow + 8 + acknow

        if (scl_busy = '1') then
          if (scl_cyc = nbyteu & "000" + nbyteu + 1) then
            scl_cyc  <= (others => '0');
            scl_busy <= '0';            
            scli     <= '1';            
          else
            if (glitch_up = '1') then
              scl_cyc <= scl_cyc + 1;
            else
              scl_cyc <= scl_cyc;
            end if;
            scl_busy <= scl_busy;
          end if;
        end if;

        if (scl_recover_busy = '1') then
          if (scl_cyc = "001010") then
            scl_cyc  <= (others => '0');
            scl_recover_busy <= '0';
          else
            if (glitch_up = '1') then
              scl_cyc <= scl_cyc + 1;
            else
              scl_cyc <= scl_cyc;
            end if;
          end if;
        end if; 

      end if;
    end if;
  end process P_SEQUENCER;

  scl_i     <= scli_dd; 
  req_ready <= scl_rdy; 
  data_out  <= data_outi;

  -- process to manage data
    P_MAIN : process (resetn, clk)
    begin
      if (resetn = '0') then
        sdai             <= '1';
        sda_rdy          <= '0';
        nw_ri            <= '0';
        oe_sda           <= '0';
        sda_temp_s       <= '0';
        flag_addr        <= '0';
        flag_err         <= '0';
        flag_succ        <= '0';
        ans_valid        <= '0';
        repetitive_start <= '0';
        req_recover      <= '0';
        sda_bit          <= (others => '0');
        sda_word         <= (others => '0');
        dly_cnt          <= (others => '0');
        i2c_data         <= (others => '0');
        data_outi        <= (others => '0');
        state_i2c        <= S0_RECOVER;
      elsif rising_edge(clk) then
        sda_temp_s <= sda_temp;
        sda_rdy    <= '0';

        if recover = '1' then
          sda_rdy                 <= '0';             
          sda_bit                 <= (others => '0'); 
          sda_word                <= (others => '0'); 
          nw_ri                   <= '0';             
          flag_addr               <= '0';                        
          flag_succ               <= '0';             
          repetitive_start        <= '0';            
          i2c_data                <= (others => '0'); 
          dly_cnt                 <= (others => '0');        
          data_outi               <= (others => '0');
          state_i2c               <= S0_RECOVER;
        end if;

        case state_i2c is

            -- I2C Bus recovery sequence (performed by master)
            -- Send a seqyìueìrnce of 10 clock cycles with SDA = '1'
            when s0_recover => 
              oe_sda      <= '0'; -- SDA = 'H'
              req_recover <= '1';
              state_i2c <= s0_rec_start;

            when s0_rec_start => 
              req_recover <= '0';
              state_i2c <= s0_rec_shift;

            when s0_rec_shift =>   
              if (scl_recover_busy = '0') then
                state_i2c <= s0_idle;
              end if;

            -- if request from requester, start routine and take sda wire  
            when s0_idle => 
              sda_rdy                 <= '0';             
              sda_bit                 <= (others => '0'); 
              sda_word                <= (others => '0'); 
              nw_ri                   <= '0';             
              flag_addr               <= '0';                        
              flag_succ               <= '0';             
              repetitive_start        <= '0';            
              i2c_data                <= (others => '0'); 
              dly_cnt                 <= (others => '0');        
              data_outi               <= (others => '0');
              
              if (req_valid = '1') then 
                sdai             <= '0';       
                oe_sda           <= '1';       
                repetitive_start <= rep_start;
                state_i2c        <= s0_start;
              else                           
                sdai      <= '1';            
                oe_sda    <= '0';                 
                state_i2c <= s0_idle;        
              end if;        
            
            -- 
            when s0_start        => 
              -- if delay has finished
              if (dly_cnt = to_unsigned(cc_halfp, dly_cnt'length)) then 
                dly_cnt   <= (others => '0');                                        
                sda_rdy   <= '1';
                i2c_data  <= address & nw_r;
                datai     <= data_in;                                                
                nw_ri     <= nw_r;                                                   
                flag_addr <= '1';                                                    
                state_i2c <= s0_setadd;                                              
              else                                                                   
                dly_cnt   <= dly_cnt + 1;                                            
                state_i2c <= s0_start;                                               
              end if;   
                       
            --  
            when s0_setadd => 
                if (dly_cnt = to_unsigned(cc_halfp, dly_cnt'length)) then 
                  sdai      <= i2c_data(7);                               
                  i2c_data  <= i2c_data(6 downto 0) & '0';                
                  sda_bit   <= sda_bit + 1;                               
                  dly_cnt   <= (others => '0');                           
                  state_i2c <= s0_shift;
                else                     
                  dly_cnt <= dly_cnt + 1;  
                end if;    
                
            --    
            when s0_shift =>

                if (nw_ri = '0' or flag_addr = '1') then 
                  oe_sda <= '1';                         
                  if (glitch_dw = '1') then              
                    sdai     <= i2c_data(7);              
                    i2c_data <= i2c_data(6 downto 0) & '0';  
                    sda_bit  <= sda_bit + 1;                 
                  end if;
                else
                  oe_sda <= '0';
                  if (glitch_up_dd = '1') then
                    i2c_data <= i2c_data(6 downto 0) & sda_temp_s;
                    sda_bit  <= sda_bit + 1;
                  end if;
                end if;

                -- write or addressing (master wait ack)
                -- else read (master set ack) 
                if (sda_bit = 8 and glitch_ack = '1' and (nw_ri = '0' or flag_addr = '1')) then                         
                  sda_word  <= sda_word + 1;
                  oe_sda    <= '0';
                  sda_bit   <= (others => '0');
                  state_i2c <= s0_ack;
                elsif (sda_bit = 8 and glitch_dw = '1' and nw_ri = '1' and flag_addr = '0') then 
                  sda_word  <= sda_word + 1;
                  oe_sda    <= '1';
                  sdai      <= '1';
                  sda_bit   <= (others => '0');
                  state_i2c <= s0_ack;
                else
                  state_i2c <= s0_shift;
                end if;

            --           
            when s0_ack => 
              -- in write operation, acknowledge comes from slaves
              if (nw_ri = '0') or (flag_addr = '1') then 
                oe_sda <= '0';                                           
                if (glitch_ack = '1') then                               
                  flag_addr <= '0';                                      
                  if (sda_temp_s = '1') then                             
                    state_i2c <= s0_end;                                 
                    flag_err  <= '1';                                    
                  else                                                   
                    if (sda_word = nbyteu) then                          
                      state_i2c <= s0_end;                               
                      flag_succ <= '1';                                  
                    else                                                 
                      i2c_data  <= datai(31 downto 24);
                      datai     <= datai(23 downto 0) & x"00";
                      state_i2c <= s0_shift; 
                    end if;                 
                  end if;
              end if;
            -- in read operation, master has to set the acknowledge 
            else                                                      
              oe_sda <= '1';                                            
              sdai   <= flag_ack;                                       
              if (scl_cnt = to_unsigned(cc_halfp, scl_cnt'length)) then 
                data_outi <= data_outi(23 downto 0) & i2c_data;         
                if (sda_word = nbyteu) then
                  flag_succ <= '1';  
                  state_i2c <= s0_end;                                                                     
                else                                                    
                  oe_sda    <= '0';                                     
                  state_i2c <= s0_shift;                                
                end if;                                                 
              end if;
            end if;
          -- take the bus and   
          -- set data = 0 
          when s0_end =>
            oe_sda <= '1'; 
            sdai   <= '0'; 
            if repetitive_start = '1' then
              sdai <= '1';
            end if;
            -- if clock has finished
            --     wait half a period
            --         set data = 1 to have stop condition
            if (scl_busy = '0') then                                  
              if (dly_cnt = to_unsigned(cc_halfp, dly_cnt'length)) then 
                sdai    <= '1';                                           
                dly_cnt <= dly_cnt + 1;
              elsif (dly_cnt = to_unsigned(2 * cc_halfp, dly_cnt'length)) then
                ans_valid <= '1';
                sdai      <= '1';
                if (ans_ready = '1') then
                  ans_valid <= '0';
                  state_i2c <= s0_idle; 
                else
                  state_i2c <= s0_end;
                end if;
              else 
                sdai      <= sdai;
                dly_cnt   <= dly_cnt + 1;
                state_i2c <= s0_end;                        
              end if;
            else
              state_i2c <= s0_end;
            end if;
          end case;
    end if;
  end process P_MAIN;
end rtl;
