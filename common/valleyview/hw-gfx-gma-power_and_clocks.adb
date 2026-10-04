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
with HW.GFX.GMA.PLLs;
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

   PUNIT_REG_DSPSSPM             : constant := 16#36#;
   DSPFREQGUAR_MASK_VLV          : constant := 3 * 2 ** 14;
   DSPFREQSTAT_MASK_VLV          : constant := 3 * 2 ** 30;
   -- vlv_calc_voltage_level() for cdclk >= 320MHz (also used for 400MHz)
   DSPFREQ_VOLTAGE_320_VLV       : constant := 2;

   VLV_CDClk                     : constant := 320_000_000;

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

   VRHUNIT_CLOCK_GATE_DISABLE    : constant := 1 * 2 ** 28;
   DPOUNIT_CLOCK_GATE_DISABLE    : constant := 1 * 2 ** 11;

   MI_ARB_DISPLAY_TRICKLE_FEED_DISABLE : constant := 1 * 2 ** 2;

   DPIO_CMNRST                   : constant := 1 * 2 ** 0;

   -- CCK fuse HPLL frequencies: 800 / 1600 / 2000 / 2400 MHz.
   subtype HPLL_VCO is Pos64 range 800_000_000 .. 2_400_000_000;

   ----------------------------------------------------------------------------

   -- The Punit power controls take two bits per well, 0 means powered
   -- and 3 means power gated. The status reads back the same way.
   procedure Power_Well_On (Well : Power_Well; Success : out Boolean)
   is
      Mask : constant Word32 :=
         Shift_Left (Word32'(3), 2 * Power_Well_Index (Well));
      Status, Ctrl : Word32;
      Timeout : Time.T;
      Timed_Out : Boolean := False;
   begin
      IOSF.Read (IOSF.PUnit, PUNIT_REG_PWRGT_STATUS, Status);
      if (Status and Mask) = 0 then
         Success := True;
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

      Success := (Status and Mask) = 0;
      pragma Debug (not Success, Debug.Put_Line
        (GNAT.Source_Info.Enclosing_Entity & ": Timed out!"));
   end Power_Well_On;

   ----------------------------------------------------------------------------

   -- Procedure (not function): IOSF.Read updates Register_State, which
   -- SPARK forbids as a function Global output.
   procedure Get_HPLL_VCO (VCO : out HPLL_VCO)
   is
      VCO_Hz : constant array (Word32 range 0 .. 3) of HPLL_VCO :=
        (800_000_000, 1_600_000_000, 2_000_000_000, 2_400_000_000);
      Fuse : Word32;
   begin
      IOSF.Read (IOSF.CCK, CCK_FUSE_REG, Fuse);
      VCO := VCO_Hz (Fuse and CCK_FUSE_HPLL_FREQ_MASK);
   end Get_HPLL_VCO;

   procedure Get_CCK_Clock
     (Register : in     Word32;
      VCO      : in     HPLL_VCO;
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

   -- Force CDClk to 320MHz. A warm reset can leave a too-low rate (e.g. the
   -- 200MHz i915 selects with all pipes off) where pipes underrun. On
   -- Valleyview, DSPSSPM is only a voltage guarantee; the actual frequency
   -- comes from CCK, so both are programmed here. i915's vlv_set_cdclk()
   -- only updates CCK for 400MHz; we always update the divider so a
   -- stuck-low CCK is corrected without needing Bunit/PFI.
   procedure Set_VLV_CDClk (VCO : HPLL_VCO; CDClk : Frequency_Type)
   is
      Divider : constant Word32 :=
         Word32 (Div_Round_Closest (2 * VCO, CDClk) - 1) and 16#1f#;
      DSPSSPM, CCK : Word32;
      Timeout : Time.T;
      Timed_Out : Boolean := False;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      IOSF.Read (IOSF.PUnit, PUNIT_REG_DSPSSPM, DSPSSPM);
      DSPSSPM := (DSPSSPM and not DSPFREQGUAR_MASK_VLV) or
                 Shift_Left (DSPFREQ_VOLTAGE_320_VLV, 14);
      IOSF.Write (IOSF.PUnit, PUNIT_REG_DSPSSPM, DSPSSPM);

      Timeout := Time.MS_From_Now (50);
      loop
         IOSF.Read (IOSF.PUnit, PUNIT_REG_DSPSSPM, DSPSSPM);
         exit when (DSPSSPM and DSPFREQSTAT_MASK_VLV) =
                   Shift_Left (DSPFREQ_VOLTAGE_320_VLV, 30) or Timed_Out;
         Timed_Out := Time.Timed_Out (Timeout);
      end loop;

      pragma Debug
        ((DSPSSPM and DSPFREQSTAT_MASK_VLV) /=
         Shift_Left (DSPFREQ_VOLTAGE_320_VLV, 30),
         Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity &
                         ": Punit voltage timed out!"));

      IOSF.Read (IOSF.CCK, CCK_DISPLAY_CLOCK_CONTROL, CCK);
      CCK := (CCK and not CCK_FREQUENCY_VALUES) or Divider;
      IOSF.Write (IOSF.CCK, CCK_DISPLAY_CLOCK_CONTROL, CCK);

      Timeout := Time.MS_From_Now (50);
      Timed_Out := False;
      loop
         IOSF.Read (IOSF.CCK, CCK_DISPLAY_CLOCK_CONTROL, CCK);
         exit when (CCK and CCK_FREQUENCY_STATUS) =
                   Shift_Left (Divider, 8) or Timed_Out;
         Timed_Out := Time.Timed_Out (Timeout);
      end loop;

      pragma Debug
        ((CCK and CCK_FREQUENCY_STATUS) /= Shift_Left (Divider, 8),
         Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity &
                         ": CCK divider timed out!"));
   end Set_VLV_CDClk;

   ----------------------------------------------------------------------------

   procedure Initialize
   is
      VCO : HPLL_VCO;
      CDClk, Raw_Clock : Int64;
      Success : Boolean;
      Ignored : Boolean;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Power_Well_On (DISP2D, Success);
      if not Success then
         return;
      end if;

      PLLs.Enable_Refclk;

      Get_HPLL_VCO (VCO);

      Get_CCK_Clock (CCK_DISPLAY_CLOCK_CONTROL, VCO, CDClk);
      -- Raise a stuck-low CDClk (e.g. 200MHz after an i915-driven warm reset).
      -- Full per-mode CDClk switching is still not implemented.
      if CDClk < VLV_CDClk then
         Set_VLV_CDClk (VCO, VLV_CDClk);
         Get_CCK_Clock (CCK_DISPLAY_CLOCK_CONTROL, VCO, CDClk);
      end if;
      Get_CCK_Clock (CCK_DISPLAY_REF_CLOCK_CONTROL, VCO, Raw_Clock);
      if CDClk in Config.CDClk_Range then
         Config.CDClk := CDClk;
      else
         Config.CDClk := Config.Default_CDClk_Freq;
      end if;
      Config.Max_CDClk := Config.CDClk;
      if Raw_Clock in Frequency_Type then
         Config.Raw_Clock := Raw_Clock;
      else
         Config.Raw_Clock := Config.Default_RawClk_Freq;
      end if;

      -- i915: vlv_init_display_clock_gating()
      -- Preserve DPOUNIT_CLOCK_GATE_DISABLE so an already-active DSI pipe
      -- does not get stuck (see i915); VRHUNIT gating is disabled.
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
         -- Same as Set_Power_Well: try each well; continue if one times out.
         Power_Well_On (Well, Ignored);
      end loop;

      -- De-assert DPIO common lane reset (i915: vlv_dpio_cmn_power_well_enable).
      Time.U_Delay (1);
      Registers.Set_Mask (Registers.VLV_DPIO_CTL, DPIO_CMNRST);
   end Initialize;

   procedure Post_All_Off is
   begin
      -- Assert common lane reset; callers run this after PLLs.All_Off.
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
