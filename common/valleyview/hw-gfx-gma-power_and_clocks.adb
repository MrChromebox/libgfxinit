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
with HW.GFX.GMA.DPIO_CHV;
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
   DP_SSC_PIPE_A_MASK            : constant := 3 * 2 ** 0;
   DP_SSS_PIPE_A_MASK            : constant := 3 * 2 ** 16;
   DSPFREQGUAR_MASK_CHV          : constant := 16#1f# * 2 ** 8;
   DSPFREQSTAT_MASK_CHV          : constant := 16#1f# * 2 ** 24;

   CHV_CDClk                     : constant := 320_000_000;

   PUNIT_REG_PWRGT_CTRL          : constant := 16#60#;
   PUNIT_REG_PWRGT_STATUS        : constant := 16#61#;

   type Power_Well is
     (DISP2D, DPIO_TX_B_01, DPIO_TX_B_23, DPIO_TX_C_01, DPIO_TX_C_23,
      DPIO_CMN_BC, DPIO_CMN_D);
   Power_Well_Index : constant array (Power_Well) of Natural :=
     (DISP2D       => 3,
      DPIO_CMN_BC  => 5,
      DPIO_TX_B_01 => 6,
      DPIO_TX_B_23 => 7,
      DPIO_TX_C_01 => 8,
      DPIO_TX_C_23 => 9,
      DPIO_CMN_D   => 12);

   PHY_Power_Well : constant array (DPIO_CHV.PHY_Type) of Power_Well :=
     (DPIO_CHV.PHY0 => DPIO_CMN_BC,
      DPIO_CHV.PHY1 => DPIO_CMN_D);

   DPLL_REF_CLK_ENABLE_VLV       : constant := 1 * 2 ** 29;
   DPLL_VGA_MODE_DIS             : constant := 1 * 2 ** 28;
   DPLL_INTEGRATED_CRI_CLK_VLV   : constant := 1 * 2 ** 14;

   type DPLL_Array is array (Pipe_Index) of Registers.Registers_Index;
   DPLL : constant DPLL_Array :=
     (Primary   => Registers.GMCH_DPLL_A,
      Secondary => Registers.GMCH_DPLL_B,
      Tertiary  => Registers.CHV_DPLL_C);

   VRHUNIT_CLOCK_GATE_DISABLE    : constant := 1 * 2 ** 28;
   DPOUNIT_CLOCK_GATE_DISABLE    : constant := 1 * 2 ** 11;

   MI_ARB_DISPLAY_TRICKLE_FEED_DISABLE : constant := 1 * 2 ** 2;

   DPIO_CMNRST                   : constant := 1 * 2 ** 0;

   ----------------------------------------------------------------------------

   -- The Punit power controls take two bits per well, 0 means powered
   -- and 3 means power gated. The status reads back the same way.
   procedure Set_Punit_Power
     (Name        : String;
      Ctrl_Reg    : Word32;
      Ctrl_Mask   : Word32;
      Status_Reg  : Word32;
      Status_Mask : Word32;
      Enable      : Boolean)
   is
      Wanted : constant Word32 := (if Enable then 0 else Status_Mask);
      Status, Ctrl : Word32;
      Timeout : Time.T;
      Timed_Out : Boolean := False;
   begin
      IOSF.Read (IOSF.PUnit, Status_Reg, Status);
      if (Status and Status_Mask) = Wanted then
         return;
      end if;

      pragma Debug (Debug.Put_Line
        (GNAT.Source_Info.Enclosing_Entity & ": " & Name &
         (if Enable then " on" else " off")));

      IOSF.Read (IOSF.PUnit, Ctrl_Reg, Ctrl);
      Ctrl := Ctrl and not Ctrl_Mask;
      if not Enable then
         Ctrl := Ctrl or Ctrl_Mask;
      end if;
      IOSF.Write (IOSF.PUnit, Ctrl_Reg, Ctrl);

      Timeout := Time.MS_From_Now (100);
      loop
         IOSF.Read (IOSF.PUnit, Status_Reg, Status);
         exit when (Status and Status_Mask) = Wanted or Timed_Out;
         Timed_Out := Time.Timed_Out (Timeout);
      end loop;

      pragma Debug
        ((Status and Status_Mask) /= Wanted,
         Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity & ": Timed out!"));
   end Set_Punit_Power;

   function Power_Well_Mask (Well : Power_Well) return Word32 is
     (Shift_Left (Word32'(3), 2 * Power_Well_Index (Well)));

   procedure Set_Power_Well (Well : Power_Well; Enable : Boolean) is
   begin
      Set_Punit_Power
        (Name        => Power_Well'Image (Well),
         Ctrl_Reg    => PUNIT_REG_PWRGT_CTRL,
         Ctrl_Mask   => Power_Well_Mask (Well),
         Status_Reg  => PUNIT_REG_PWRGT_STATUS,
         Status_Mask => Power_Well_Mask (Well),
         Enable      => Enable);
   end Set_Power_Well;

   procedure Power_Well_On (Well : Power_Well) is
   begin
      Set_Power_Well (Well, True);
   end Power_Well_On;

   function Power_Well_Is_On (Well : Power_Well) return Boolean
   is
      Status : Word32;
   begin
      IOSF.Read (IOSF.PUnit, PUNIT_REG_PWRGT_STATUS, Status);
      return (Status and Power_Well_Mask (Well)) = 0;
   end Power_Well_Is_On;

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

   -- The CDClk is requested from the Punit, and a warm reset keeps the
   -- last request, e.g. the 200MHz i915 asks for once all pipes are off.
   -- Pipes underrun at that rate, and as we don't switch the CDClk per
   -- mode, we always run at the 320MHz maximum.
   procedure Set_CHV_CDClk (VCO : Int64; CDClk : Pos64)
   is
      Divider : constant Word32 :=
         Word32 (Div_Round_Closest (2 * VCO, CDClk) - 1) and 16#1f#;
      DSPSSPM : Word32;
      Timeout : Time.T;
      Timed_Out : Boolean := False;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      IOSF.Read (IOSF.PUnit, PUNIT_REG_DSPSSPM, DSPSSPM);
      DSPSSPM := (DSPSSPM and not DSPFREQGUAR_MASK_CHV) or
                 Shift_Left (Divider, 8);
      IOSF.Write (IOSF.PUnit, PUNIT_REG_DSPSSPM, DSPSSPM);

      Timeout := Time.MS_From_Now (50);
      loop
         IOSF.Read (IOSF.PUnit, PUNIT_REG_DSPSSPM, DSPSSPM);
         exit when (DSPSSPM and DSPFREQSTAT_MASK_CHV) =
                   Shift_Left (Divider, 24) or Timed_Out;
         Timed_Out := Time.Timed_Out (Timeout);
      end loop;

      pragma Debug
        ((DSPSSPM and DSPFREQSTAT_MASK_CHV) /= Shift_Left (Divider, 24),
         Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity & ": Timed out!"));
   end Set_CHV_CDClk;

   ----------------------------------------------------------------------------

   -- The lanes of the Braswell PHYs are powered through DISPLAY_PHY_CONTROL,
   -- which is handled by PLLs. Here, we only power the common lanes.
   procedure Initialize_CHV_PHYs
   is
      type PHY_Bool_Array is array (DPIO_CHV.PHY_Type) of Boolean;
      PHY_On : PHY_Bool_Array;
   begin
      for PHY in DPIO_CHV.PHY_Type loop
         PHY_On (PHY) := Power_Well_Is_On (PHY_Power_Well (PHY));
      end loop;
      PLLs.PHY_Control_Init
        (PHY0_On => PHY_On (DPIO_CHV.PHY0),
         PHY1_On => PHY_On (DPIO_CHV.PHY1));

      for PHY in DPIO_CHV.PHY_Type loop
         if not PHY_On (PHY) then
            Time.U_Delay (1);
            Power_Well_On (PHY_Power_Well (PHY));
            DPIO_CHV.Common_Lane_Init (PHY);
            PLLs.PHY_Common_Lane_Reset_Deassert (PHY);
         end if;
      end loop;
   end Initialize_CHV_PHYs;

   procedure Initialize
   is
      VCO : constant Int64 := HPLL_VCO;
      CDClk, Raw_Clock : Int64;
      DPIO_Ctl : Word32;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      if Config.Has_CHV_PHY then
         -- There is no DISP2D well, the display is powered with pipe A.
         Set_Punit_Power
           (Name        => "PIPE_A",
            Ctrl_Reg    => PUNIT_REG_DSPSSPM,
            Ctrl_Mask   => DP_SSC_PIPE_A_MASK,
            Status_Reg  => PUNIT_REG_DSPSSPM,
            Status_Mask => DP_SSS_PIPE_A_MASK,
            Enable      => True);
      else
         Power_Well_On (DISP2D);
      end if;

      -- Enable the CRI clock source and the reference clocks
      for Pipe in Primary .. Config.Max_Pipe loop
         Registers.Set_Mask
           (Register => DPLL (Pipe),
            Mask     => DPLL_REF_CLK_ENABLE_VLV or DPLL_VGA_MODE_DIS or
                        (if Pipe = Primary
                         then 0 else DPLL_INTEGRATED_CRI_CLK_VLV));
      end loop;

      if Config.Has_CHV_PHY then
         Set_CHV_CDClk (VCO, CHV_CDClk);
      end if;
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

      if Config.Has_CHV_PHY then
         Initialize_CHV_PHYs;
         return;
      end if;

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
      if Config.Has_CHV_PHY then
         for PHY in DPIO_CHV.PHY_Type loop
            PLLs.PHY_Common_Lane_Reset_Assert (PHY);
            Set_Power_Well (PHY_Power_Well (PHY), False);
         end loop;
      else
         Registers.Unset_Mask (Registers.VLV_DPIO_CTL, DPIO_CMNRST);
      end if;
   end Post_All_Off;

   procedure Limit_Dotclocks
     (Configs        : in out Pipe_Configs;
      CDClk_Switch   :    out Boolean)
   is
   begin
      if Config.Has_CHV_PHY then
         Config_Helpers.Limit_Dotclocks (Configs, Config.CDClk * 95 / 100);

         -- The DPLL can't generate TMDS clocks between 216MHz and 240MHz.
         for Pipe in Pipe_Index loop
            declare
               Port : constant Port_Type := Configs (Pipe).Port;
               Dotclock : Frequency_Type renames Configs (Pipe).Mode.Dotclock;
            begin
               if Port in Active_Port_Type and then
                  Config_Helpers.To_Display_Type (Port) = HDMI and then
                  Dotclock > 216_000_000 and then Dotclock < 240_000_000
               then
                  Dotclock := 216_000_000;
               end if;
            end;
         end loop;
      else
         Config_Helpers.Limit_Dotclocks (Configs, Config.CDClk * 90 / 100);
      end if;
      CDClk_Switch := False;
   end Limit_Dotclocks;

   procedure Power_Up (Port : Active_Port_Type; Success : out Boolean) is
   begin
      Success := True;
   end Power_Up;

end HW.GFX.GMA.Power_And_Clocks;
