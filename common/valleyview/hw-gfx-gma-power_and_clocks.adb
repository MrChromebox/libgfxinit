--
-- Copyright (C) 2020 Angel Pons <th3fanbus@gmail.com>
-- Copyright (C) 2026 Matt DeVillier <matt.devillier@gmail.com>
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 2 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--

with HW.Time;
with HW.GFX.GMA.Config;
with HW.GFX.GMA.IOSF;
with HW.GFX.GMA.Registers;

with HW.Debug;
with GNAT.Source_Info;

package body HW.GFX.GMA.Power_And_Clocks is

   CCK_FUSE_REG                  : constant := 16#08#;
   CCK_FUSE_HPLL_FREQ_MASK       : constant := 16#03#;
   CCK_DISPLAY_CLOCK_CONTROL     : constant := 16#6b#;
   CCK_DISPLAY_REF_CLOCK_CONTROL : constant := 16#6c#;
   CCK_FREQUENCY_VALUES          : constant := 16#1f# * 2 ** 0;
   CCK_FREQUENCY_STATUS          : constant := 16#1f# * 2 ** 8;

   CCU_DISPLAY_CLOCKS            : constant := 16#0114#;
   CCU_DISPLAY_SSC_AND_BEND      : constant := 16#0003_0003#;

   PUNIT_REG_PWRGT_CTRL          : constant := 16#60#;
   PUNIT_REG_PWRGT_STATUS        : constant := 16#61#;

   type Power_Well is
     (DISP2D, DPIO_TX_B_01, DPIO_TX_B_23, DPIO_TX_C_01, DPIO_TX_C_23,
      DPIO_CMN_BC);
   Power_Well_Index : constant array (Power_Well) of Natural :=
     (DISP2D       => 3,
      DPIO_CMN_BC  => 5,
      DPIO_TX_B_01 => 6,
      DPIO_TX_B_23 => 7,
      DPIO_TX_C_01 => 8,
      DPIO_TX_C_23 => 9);

   DPLL_REF_CLK_ENABLE_VLV       : constant := 1 * 2 ** 29;
   DPLL_VGA_MODE_DIS             : constant := 1 * 2 ** 28;
   DPLL_INTEGRATED_CRI_CLK_VLV   : constant := 1 * 2 ** 14;

   VRHUNIT_CLOCK_GATE_DISABLE    : constant := 1 * 2 ** 28;
   DPOUNIT_CLOCK_GATE_DISABLE    : constant := 1 * 2 ** 11;

   MI_ARB_DISPLAY_TRICKLE_FEED_DISABLE : constant := 1 * 2 ** 2;

   DPIO_CMNRST                   : constant := 1 * 2 ** 0;

   ----------------------------------------------------------------------------

   procedure Power_Well_On (Well : Power_Well)
   is
      Mask : constant Word32 :=
         Shift_Left (Word32'(3), 2 * Power_Well_Index (Well));
      Status, Ctrl : Word32;
      Timeout : Time.T;
      Timed_Out : Boolean := False;
   begin
      IOSF.Read (IOSF.PUnit, PUNIT_REG_PWRGT_STATUS, Status);
      if (Status and Mask) = 0 then
         return;
      end if;

      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity & ": " &
                                    Power_Well'Image (Well)));

      IOSF.Read (IOSF.PUnit, PUNIT_REG_PWRGT_CTRL, Ctrl);
      IOSF.Write (IOSF.PUnit, PUNIT_REG_PWRGT_CTRL, Ctrl and not Mask);

      Timeout := Time.MS_From_Now (100);
      loop
         IOSF.Read (IOSF.PUnit, PUNIT_REG_PWRGT_STATUS, Status);
         exit when (Status and Mask) = 0 or Timed_Out;
         Timed_Out := Time.Timed_Out (Timeout);
      end loop;

      pragma Debug ((Status and Mask) /= 0, Debug.Put_Line
        (GNAT.Source_Info.Enclosing_Entity & ": Timed out!"));
   end Power_Well_On;

   ----------------------------------------------------------------------------

   function HPLL_VCO return Int64
   is
      VCO_MHz : constant array (Word32 range 0 .. 3) of Int64 :=
        (800, 1600, 2000, 2400);
      Fuse : Word32;
   begin
      IOSF.Read (IOSF.CCK, CCK_FUSE_REG, Fuse);
      return VCO_MHz (Fuse and CCK_FUSE_HPLL_FREQ_MASK) * 1_000_000;
   end HPLL_VCO;

   procedure Get_CCK_Clock
     (Register : in     Word32;
      VCO      : in     Int64;
      Clock    :    out Int64)
   is
      Value : Word32;
      Divider : Word32;
   begin
      IOSF.Read (IOSF.CCK, Register, Value);
      Divider := Value and CCK_FREQUENCY_VALUES;
      pragma Debug
        (Shift_Left (Divider, 8) /= (Value and CCK_FREQUENCY_STATUS),
         Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity &
                         ": Clock change in progress!"));
      Clock := Div_Round_Closest (2 * VCO, Pos64 (Divider + 1));
   end Get_CCK_Clock;

   ----------------------------------------------------------------------------

   procedure Initialize
   is
      VCO : constant Int64 := HPLL_VCO;
      CDClk, Raw_Clock : Int64;
      DPIO_Ctl : Word32;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Power_Well_On (DISP2D);

      -- Enable the CRI clock source and the reference clocks
      Registers.Set_Mask
        (Register => Registers.GMCH_DPLL_A,
         Mask     => DPLL_REF_CLK_ENABLE_VLV or DPLL_VGA_MODE_DIS);
      Registers.Set_Mask
        (Register => Registers.GMCH_DPLL_B,
         Mask     => DPLL_REF_CLK_ENABLE_VLV or DPLL_VGA_MODE_DIS or
                     DPLL_INTEGRATED_CRI_CLK_VLV);

      Get_CCK_Clock (CCK_DISPLAY_CLOCK_CONTROL, VCO, CDClk);
      Get_CCK_Clock (CCK_DISPLAY_REF_CLOCK_CONTROL, VCO, Raw_Clock);
      if CDClk in Config.CDClk_Range then
         Config.CDClk := CDClk;
      else
         Config.CDClk := Config.Default_CDClk_Freq;
      end if;
      -- No CDClk switching yet
      Config.Max_CDClk := Config.CDClk;
      if Raw_Clock in Frequency_Type then
         Config.Raw_Clock := Raw_Clock;
      else
         Config.Raw_Clock := Config.Default_RawClk_Freq;
      end if;

      -- i915: vlv_init_display_clock_gating()
      Registers.Unset_And_Set_Mask
        (Register    => Registers.VLV_DSPCLK_GATE_D,
         Mask_Unset  => not DPOUNIT_CLOCK_GATE_DISABLE,
         Mask_Set    => VRHUNIT_CLOCK_GATE_DISABLE);
      Registers.Write
        (Register => Registers.VLV_MI_ARB,
         Value    => MI_ARB_DISPLAY_TRICKLE_FEED_DISABLE);
      Registers.Write (Registers.VLV_CBR1, 0);
      Registers.Write
        (Register => Registers.VLV_RAWCLK_FREQ,
         Value    => Word32 (Div_Round_Closest (Config.Raw_Clock, 1_000_000)));
      Registers.Write
        (Register => Registers.VLV_GMBUSFREQ,
         Value    => Word32 (Div_Round_Up (Config.CDClk, 1_000_000)));

      -- Request spread spectrum and bend clocks for the display PLLs.
      IOSF.Unset_And_Set_Mask
        (Unit        => IOSF.CCU,
         Register    => CCU_DISPLAY_CLOCKS,
         Mask_Unset  => 0,
         Mask_Set    => CCU_DISPLAY_SSC_AND_BEND);

      for Well in DPIO_TX_B_01 .. DPIO_CMN_BC loop
         Power_Well_On (Well);
      end loop;

      -- Common lane reset must only be released with both PLLs
      -- disabled, so we keep it if it was already released.
      Registers.Read (Registers.VLV_DPIO_CTL, DPIO_Ctl);
      if (DPIO_Ctl and DPIO_CMNRST) = 0 then
         Time.U_Delay (1);
         Registers.Set_Mask (Registers.VLV_DPIO_CTL, DPIO_CMNRST);
      end if;
   end Initialize;

   procedure Post_All_Off is
   begin
      -- Assert common lane reset, all PLLs are disabled by now.
      Registers.Unset_Mask (Registers.VLV_DPIO_CTL, DPIO_CMNRST);
   end Post_All_Off;

   procedure Limit_Dotclocks
     (Configs        : in out Pipe_Configs;
      CDClk_Switch   :    out Boolean)
   is
   begin
      Config_Helpers.Limit_Dotclocks (Configs, Config.CDClk * 90 / 100);
      CDClk_Switch := False;
   end Limit_Dotclocks;

   procedure Power_Up (Port : Active_Port_Type; Success : out Boolean) is
   begin
      Success := True;
   end Power_Up;

end HW.GFX.GMA.Power_And_Clocks;
