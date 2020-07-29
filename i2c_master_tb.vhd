library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
--
library vunit_lib;
context vunit_lib.vunit_context;
-- use vunit_lib.array_pkg.all;
-- use vunit_lib.lang.all;
-- use vunit_lib.string_ops.all;
-- use vunit_lib.dictionary.all;
-- use vunit_lib.path.all;
-- use vunit_lib.log_types_pkg.all;
-- use vunit_lib.log_special_types_pkg.all;
-- use vunit_lib.log_pkg.all;
-- use vunit_lib.check_types_pkg.all;
-- use vunit_lib.check_special_types_pkg.all;
-- use vunit_lib.check_pkg.all;
-- use vunit_lib.run_types_pkg.all;
-- use vunit_lib.run_special_types_pkg.all;
-- use vunit_lib.run_base_pkg.all;
-- use vunit_lib.run_pkg.all;
--
library uvvm_util;
context uvvm_util.uvvm_util_context;
use uvvm_util.methods_pkg.all;

--
library bitvis_vip_i2c;
use bitvis_vip_i2c.i2c_bfm_pkg.all;

entity i2c_master_tb is
  generic (runner_cfg : string);
end;

architecture bench of i2c_master_tb is


  -- Clock period
  constant clk_period : time := 5 ns;
  -- Generics
  constant cc_halfp : integer := 20;

  constant C_I2C_BFM_CONFIG : t_i2c_bfm_config := (
    enable_10_bits_addressing       => false,
    master_sda_to_scl               => 20 ns,
    master_scl_to_sda               => 20 ns,
    master_stop_condition_hold_time => 20 ns,
    max_wait_scl_change             => 10 ms,
    max_wait_scl_change_severity    => failure,
    max_wait_sda_change             => 10 ms,
    max_wait_sda_change_severity    => failure,
    i2c_bit_time                    => cc_halfp*2*clk_period,
    i2c_bit_time_severity           => failure,
    acknowledge_severity            => failure,
    slave_mode_address              => "0001000100",
    slave_mode_address_severity     => failure,
    slave_rw_bit_severity           => failure,
    reserved_address_severity       => warning,
    match_strictness                => MATCH_EXACT,
    id_for_bfm                      => ID_BFM,
    id_for_bfm_wait                 => ID_BFM_WAIT,
    id_for_bfm_poll                 => ID_BFM_POLL
    );

  -- Ports
  signal resetn : std_logic;
  signal clk : std_logic;
  signal nbyte : std_logic_vector(5 downto 0);
  signal address : std_logic_vector(6 downto 0);
  signal nw_r : std_logic;
  signal data_in : std_logic_vector(31 downto 0);
  signal data_out : std_logic_vector(31 downto 0);
  signal rep_start : std_logic;
  signal req_valid : std_logic;
  signal req_ready : std_logic;
  signal ans_valid : std_logic;
  signal ans_ready : std_logic;
  signal flag_ack : std_logic;
  signal stri : std_logic;
  signal flag_err  : std_logic;
  signal recover   : std_logic;

  signal myReg0 : std_logic_vector(7 downto 0) ;
  signal myReg1 : std_logic_vector(7 downto 0) ;
  signal myReg2 : std_logic_vector(7 downto 0) ;
  signal myReg3 : std_logic_vector(7 downto 0) ;
  signal myReg4 : std_logic_vector(7 downto 0) ;
  signal myReg5 : std_logic_vector(7 downto 0) ;
  signal myReg6 : std_logic_vector(7 downto 0) ;
  signal myReg7 : std_logic_vector(7 downto 0) ; 

  signal i2c_if : t_i2c_if;


begin

  i2c_if.scl <= 'H';
  i2c_if.sda <= 'H';

  i2c_master_inst : entity work.i2c_master
    generic map (
      cc_halfp => cc_halfp
    )
    port map (
      resetn => resetn,
      clk => clk,
      nbyte => nbyte,
      address => address,
      nw_r => nw_r,
      data_in => data_in,
      data_out => data_out,
      rep_start => rep_start,
      req_valid => req_valid,
      req_ready => req_ready,
      ans_valid => ans_valid,
      ans_ready => ans_ready,
      flag_ack => flag_ack,
      flag_err => flag_err,
      stri => stri,
      recover => recover,
      scl => i2c_if.scl,
      sda => i2c_if.sda
    );

    i2cSlave_inst : entity work.i2cSlave
    port map(
      clk           =>     clk,     
      rst           =>     not(resetn),    
      sda           =>     i2c_if.sda,
      scl           =>     i2c_if.scl,       
      myReg0        =>      myReg0,     
      myReg1        =>      myReg1,
      myReg2        =>      myReg2,
      myReg3        =>      myReg3,
      myReg4        =>      myReg4,
      myReg5        =>      myReg5,
      myReg6        =>      myReg6,
      myReg7        =>      myReg7       

    );

  main : process


     variable v_data_out : t_byte_array(0 to 0);

      procedure i2c_slave_receive (
        variable data         : out  t_byte_array;
        constant msg                : in  string) is
      begin
        i2c_slave_receive(data, -- keep as is
                          msg, -- keep as is
                            i2c_if.scl,
                            i2c_if.sda,
                            C_WRITE_BIT, -- 
                            "I2C BFM",
                            shared_msg_id_panel,
                            C_I2C_BFM_CONFIG); -- Use locally defined configuration or C_I2C_BFM_CONFIG_DEFAULT 
      end;  
  begin

    
    nbyte <= "000001";
    address <= "1000100";
    nw_r <= '0';
    data_in <= X"000055AA";

    rep_start <= '0';
    req_valid <= '1';
    ans_ready <= '1';
    flag_ack  <= '0';
    stri <= '0';
	recover <= '0';

    resetn <= '0';        
    wait for 20*clk_period;
    resetn <= '1';
    wait for 5*clk_period;

    test_runner_setup(runner, runner_cfg);
    while test_suite loop
      if run("test_alive") then
        info("Hello world test_alive");
        i2c_if <= init_i2c_if_signals(VOID);


        wait for 100 ns;
        test_runner_cleanup(runner);
        
      elsif run("test_0") then
        info("Hello world test_0");

        i2c_if <= init_i2c_if_signals(VOID);
        i2c_slave_receive(v_data_out, "Receive from Master");

        wait for 10 us;

        test_runner_cleanup(runner);
      end if;
    end loop;
  end process main;

   clk_process : process
   begin
     clk <= '1';
     wait for clk_period/2;
     clk <= '0';
     wait for clk_period/2;
   end process clk_process;

end;
