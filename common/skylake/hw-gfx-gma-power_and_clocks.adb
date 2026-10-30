--
-- Copyright (C) 2014-2016, 2019 secunet Security Networks AG
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

with GNAT.Source_Info;

with HW.Time;
with HW.Debug;
with HW.GFX.GMA.Config;
with HW.GFX.GMA.Registers;
with HW.GFX.GMA.PCode;
with HW.GFX.GMA.Transcoder;

use type HW.Word64;

package body HW.GFX.GMA.Power_And_Clocks is

   type Power_Domain is (MISC_IO, PW1, PW2, DDI_AE, DDI_B, DDI_C, DDI_D);
   subtype Power_Well is Power_Domain range PW1 .. PW2;
   subtype Dynamic_Domain is Power_Domain range PW2 .. DDI_D;

   NDE_RSTWRN_OPT_RST_PCH_Handshake_En : constant := 1 * 2 **  4;

   FUSE_STATUS_DOWNLOAD_STATUS         : constant := 1 * 2 ** 31;
   FUSE_STATUS_PG0_DIST_STATUS         : constant := 1 * 2 ** 27;

   DFSM_DISPLAY_CDCLK_LIMIT_675MHZ     : constant := 0 * 2 ** 23;
   DFSM_DISPLAY_CDCLK_LIMIT_540MHZ     : constant := 1 * 2 ** 23;
   DFSM_DISPLAY_CDCLK_LIMIT_450MHZ     : constant := 2 * 2 ** 23;
   DFSM_DISPLAY_CDCLK_LIMIT_337_5MHZ   : constant := 3 * 2 ** 23;
   DFSM_DISPLAY_CDCLK_LIMIT_MASK       : constant := 3 * 2 ** 23;

   SFUSE_STRAP_RAW_FREQUENCY           : constant := 1 * 2 **  8;

   type Power_Domain_Values is array (Power_Domain) of Word32;
   PWR_WELL_CTL_POWER_REQUEST : constant Power_Domain_Values :=
     (MISC_IO  => 1 * 2 **  1,
      DDI_AE   => 1 * 2 **  3,
      DDI_B    => 1 * 2 **  5,
      DDI_C    => 1 * 2 **  7,
      DDI_D    => 1 * 2 **  9,
      PW1      => 1 * 2 ** 29,
      PW2      => 1 * 2 ** 31);
   PWR_WELL_CTL_POWER_STATE : constant Power_Domain_Values :=
     (MISC_IO  => 1 * 2 **  0,
      DDI_AE   => 1 * 2 **  2,
      DDI_B    => 1 * 2 **  4,
      DDI_C    => 1 * 2 **  6,
      DDI_D    => 1 * 2 **  8,
      PW1      => 1 * 2 ** 28,
      PW2      => 1 * 2 ** 30);

   type Power_Well_Values is array (Power_Well) of Word32;
   FUSE_STATUS_PGx_DIST_STATUS : constant Power_Well_Values :=
     (PW1   => 1 * 2 ** 26,
      PW2   => 1 * 2 ** 25);

   DBUF_CTL_DBUF_POWER_REQUEST         : constant := 1 * 2 ** 31;
   DBUF_CTL_DBUF_POWER_STATE           : constant := 1 * 2 ** 30;

   ----------------------------------------------------------------------------

   DPLL_CTRL1_DPLL0_LINK_RATE_MASK     : constant := 7 * 2 **  1;
   DPLL_CTRL1_DPLL0_LINK_RATE_2700MHZ  : constant := 0 * 2 **  1;
   DPLL_CTRL1_DPLL0_LINK_RATE_1350MHZ  : constant := 1 * 2 **  1;
   DPLL_CTRL1_DPLL0_LINK_RATE_810MHZ   : constant := 2 * 2 **  1;
   DPLL_CTRL1_DPLL0_LINK_RATE_1620MHZ  : constant := 3 * 2 **  1;
   DPLL_CTRL1_DPLL0_LINK_RATE_1080MHZ  : constant := 4 * 2 **  1;
   DPLL_CTRL1_DPLL0_LINK_RATE_2160MHZ  : constant := 5 * 2 **  1;
   DPLL_CTRL1_DPLL0_OVERRIDE           : constant := 1 * 2 **  0;
   DPLL_CTRL1_DPLL0_SSC                : constant := 1 * 2 **  4;
   DPLL_CTRL1_DPLL0_HDMI_MODE          : constant := 1 * 2 **  5;

   LCPLL1_CTL_PLL_ENABLE               : constant := 1 * 2 ** 31;
   LCPLL1_CTL_PLL_LOCK                 : constant := 1 * 2 ** 30;

   DISP_FBC_MEMORY_WAKE                : constant := 1 * 2 ** 31;

   ----------------------------------------------------------------------------

   CDCLK_CTL_CD_FREQ_SELECT_MASK       : constant := 3 * 2 ** 26;
   CDCLK_CTL_CD_FREQ_SELECT_450MHZ     : constant := 0 * 2 ** 26;
   CDCLK_CTL_CD_FREQ_SELECT_540MHZ     : constant := 1 * 2 ** 26;
   CDCLK_CTL_CD_FREQ_SELECT_337_5MHZ   : constant := 2 * 2 ** 26;
   CDCLK_CTL_CD_FREQ_SELECT_675MHZ     : constant := 3 * 2 ** 26;
   CDCLK_CTL_CD_FREQ_DECIMAL_MASK      : constant :=     16#7ff#;
   CDCLK_CTL_DIVMUX_CD_OVERRIDE        : constant := 1 * 2 ** 19;

   SKL_PCODE_CDCLK_CONTROL             : constant := 7;
   SKL_CDCLK_PREPARE_FOR_CHANGE        : constant := 3;
   SKL_CDCLK_READY_FOR_CHANGE          : constant := 1;

   function CDCLK_CTL_CD_FREQ_DECIMAL (CDClk : Frequency_Type) return Word32 is
   begin
      -- Weirdest representation: CDClk - 1MHz in 10.1 (10 + 1 fractional bit)
      return Word32 ((CDClk - 1_000_000) / 500_000);
   end CDCLK_CTL_CD_FREQ_DECIMAL;

   ----------------------------------------------------------------------------

   procedure PD_Off (PD : Power_Domain)
   is
      Ctl1, Ctl2, Ctl3, Ctl4 : Word32;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Registers.Read (Registers.PWR_WELL_CTL_BIOS, Ctl1);
      Registers.Read (Registers.PWR_WELL_CTL_DRIVER, Ctl2);
      Registers.Read (Registers.PWR_WELL_CTL_KVMR, Ctl3);
      Registers.Read (Registers.PWR_WELL_CTL_DEBUG, Ctl4);
      pragma Debug (Registers.Posting_Read (Registers.PWR_WELL_CTL5)); --  Result for debugging only
      pragma Debug (Registers.Posting_Read (Registers.PWR_WELL_CTL6)); --  Result for debugging only

      if ((Ctl1 or Ctl2 or Ctl3 or Ctl4) and
          PWR_WELL_CTL_POWER_REQUEST (PD)) /= 0
      then
         Registers.Wait_Set_Mask
           (Register => Registers.PWR_WELL_CTL_DRIVER,
            Mask     => PWR_WELL_CTL_POWER_STATE (PD));
      end if;

      if (Ctl1 and PWR_WELL_CTL_POWER_REQUEST (PD)) /= 0 then
         Registers.Unset_Mask
           (Register => Registers.PWR_WELL_CTL_BIOS,
            Mask     => PWR_WELL_CTL_POWER_REQUEST (PD));
      end if;

      if (Ctl2 and PWR_WELL_CTL_POWER_REQUEST (PD)) /= 0 then
         Registers.Unset_Mask
           (Register => Registers.PWR_WELL_CTL_DRIVER,
            Mask     => PWR_WELL_CTL_POWER_REQUEST (PD));
      end if;
   end PD_Off;

   procedure PD_On (PD : Power_Domain)
   with
      Pre => True
   is
      Ctl1, Ctl2, Ctl3, Ctl4 : Word32;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Registers.Read (Registers.PWR_WELL_CTL_BIOS, Ctl1);
      Registers.Read (Registers.PWR_WELL_CTL_DRIVER, Ctl2);
      Registers.Read (Registers.PWR_WELL_CTL_KVMR, Ctl3);
      Registers.Read (Registers.PWR_WELL_CTL_DEBUG, Ctl4);
      pragma Debug (Registers.Posting_Read (Registers.PWR_WELL_CTL5)); --  Result for debugging only
      pragma Debug (Registers.Posting_Read (Registers.PWR_WELL_CTL6)); --  Result for debugging only

      if ((Ctl1 or Ctl2 or Ctl3 or Ctl4) and
          PWR_WELL_CTL_POWER_REQUEST (PD)) = 0
      then
         Registers.Wait_Unset_Mask
           (Register => Registers.PWR_WELL_CTL_DRIVER,
            Mask     => PWR_WELL_CTL_POWER_STATE (PD));
      end if;

      if (Ctl2 and PWR_WELL_CTL_POWER_REQUEST (PD)) = 0 then
         Registers.Set_Mask
           (Register => Registers.PWR_WELL_CTL_DRIVER,
            Mask     => PWR_WELL_CTL_POWER_REQUEST (PD));
         Registers.Wait_Set_Mask
           (Register => Registers.PWR_WELL_CTL_DRIVER,
            Mask     => PWR_WELL_CTL_POWER_STATE (PD));

         if PD in Power_Well then
            Registers.Wait_Set_Mask
              (Register => Registers.FUSE_STATUS,
               Mask     => FUSE_STATUS_PGx_DIST_STATUS (PD));
         end if;
      end if;
   end PD_On;

   function Need_PD (PD : Dynamic_Domain; Configs : Pipe_Configs) return Boolean
   is
   begin
      return (case PD is
         when DDI_AE    => Configs (Primary).Port = eDP or
                           Configs (Secondary).Port = eDP or
                           Configs (Tertiary).Port = eDP,
         when DDI_B     => Configs (Primary).Port = HDMI1 or
                           Configs (Primary).Port = DP1 or
                           Configs (Secondary).Port = HDMI1 or
                           Configs (Secondary).Port = DP1 or
                           Configs (Tertiary).Port = HDMI1 or
                           Configs (Tertiary).Port = DP1,
         when DDI_C     => Configs (Primary).Port = HDMI2 or
                           Configs (Primary).Port = DP2 or
                           Configs (Secondary).Port = HDMI2 or
                           Configs (Secondary).Port = DP2 or
                           Configs (Tertiary).Port = HDMI2 or
                           Configs (Tertiary).Port = DP2,
         when DDI_D     => Configs (Primary).Port = HDMI3 or
                           Configs (Primary).Port = DP3 or
                           Configs (Secondary).Port = HDMI3 or
                           Configs (Secondary).Port = DP3 or
                           Configs (Tertiary).Port = HDMI3 or
                           Configs (Tertiary).Port = DP3,
         when PW2       => (Configs (Primary).Port /= Disabled and
                            Configs (Primary).Port /= eDP) or
                           Configs (Secondary).Port /= Disabled or
                           Configs (Tertiary).Port /= Disabled);
   end Need_PD;

   ----------------------------------------------------------------------------

   procedure Pre_All_Off is
   begin
      Transcoder.PSR_Off;
   end Pre_All_Off;

   procedure Post_All_Off is
   begin
      for PD in reverse Dynamic_Domain loop
         PD_Off (PD);
      end loop;

      Registers.Unset_Mask
        (Register    => Registers.DBUF_CTL_S0,
         Mask        => DBUF_CTL_DBUF_POWER_REQUEST);
      Registers.Wait_Unset_Mask
        (Register    => Registers.DBUF_CTL_S0,
         Mask        => DBUF_CTL_DBUF_POWER_STATE);

      Registers.Unset_Mask
        (Register    => Registers.LCPLL1_CTL,
         Mask        => LCPLL1_CTL_PLL_ENABLE);
      Registers.Wait_Unset_Mask
        (Register    => Registers.LCPLL1_CTL,
         Mask        => LCPLL1_CTL_PLL_LOCK);

      PD_Off (MISC_IO);
      PD_Off (PW1);
   end Post_All_Off;

   -- Rates for the 8.64 GHz DPLL0 VCO (eDP 1.4 2.16/4.32 Gbps). The
   -- 8.1 GHz rates (337.5/450/675) are a different VCO; i915 will not
   -- keep a mix of the two across a DC5/DC6 exit.
   function Normalize_CDClk (CDClk : in Int64) return Config.CDClk_Range is
     (   if CDClk <= 308_571_000 then 308_571_000
      elsif CDClk <= 432_000_000 then 432_000_000
      elsif CDClk <= 540_000_000 then 540_000_000
                                 else 617_143_000);

   procedure Get_Cur_CDClk (CDClk : out Config.CDClk_Range)
   is
      CDCLK_CTL : Word32;
   begin
      Registers.Read (Registers.CDCLK_CTL, CDCLK_CTL);
      CDCLK_CTL := CDCLK_CTL and CDCLK_CTL_CD_FREQ_DECIMAL_MASK;
      CDClk := Normalize_CDClk (Int64 (CDCLK_CTL) * 500_000 + 1_000_000);
   end Get_Cur_CDClk;

   procedure Get_Max_CDClk (CDClk : out Config.CDClk_Range)
   is
      DFSM : Word32;
   begin
      Registers.Read (Registers.DFSM, DFSM);
      CDClk :=
        (case DFSM and DFSM_DISPLAY_CDCLK_LIMIT_MASK is
            when DFSM_DISPLAY_CDCLK_LIMIT_675MHZ   => 617_143_000,
            when DFSM_DISPLAY_CDCLK_LIMIT_540MHZ   => 540_000_000,
            when DFSM_DISPLAY_CDCLK_LIMIT_450MHZ   => 432_000_000,
            when others                            => 308_571_000);
   end Get_Max_CDClk;

   procedure Set_CDClk (CDClk_In : Frequency_Type)
   is
      CDClk : constant Config.CDClk_Range :=
         Normalize_CDClk (Frequency_Type'Min (CDClk_In, Config.Max_CDClk));
      Success : Boolean;

      -- 1080/2160 MHz link rates are the 8.64 GHz VCO. i915 uses 1080 MHz,
      -- the lowest rate for that VCO.
      function DPLL0_VCO_Is_864 return Boolean
      is
         PLL_Enabled, PLL_Locked : Boolean;
         Ctrl : Word32;
      begin
         Registers.Is_Set_Mask
           (Register => Registers.LCPLL1_CTL,
            Mask     => LCPLL1_CTL_PLL_ENABLE,
            Result   => PLL_Enabled);
         Registers.Is_Set_Mask
           (Register => Registers.LCPLL1_CTL,
            Mask     => LCPLL1_CTL_PLL_LOCK,
            Result   => PLL_Locked);
         if not (PLL_Enabled and PLL_Locked) then
            return False;
         end if;

         Registers.Read (Registers.DPLL_CTRL1, Ctrl);
         if (Ctrl and (DPLL_CTRL1_DPLL0_HDMI_MODE or
                       DPLL_CTRL1_DPLL0_SSC or
                       DPLL_CTRL1_DPLL0_OVERRIDE)) /=
            DPLL_CTRL1_DPLL0_OVERRIDE
         then
            return False;
         end if;

         case Ctrl and DPLL_CTRL1_DPLL0_LINK_RATE_MASK is
            when DPLL_CTRL1_DPLL0_LINK_RATE_1080MHZ |
                 DPLL_CTRL1_DPLL0_LINK_RATE_2160MHZ =>
               return True;
            when others =>
               return False;
         end case;
      end DPLL0_VCO_Is_864;

      procedure Disable_DPLL0
      is
         PLL_Enabled : Boolean;
      begin
         Registers.Is_Set_Mask
           (Register => Registers.LCPLL1_CTL,
            Mask     => LCPLL1_CTL_PLL_ENABLE,
            Result   => PLL_Enabled);
         if PLL_Enabled then
            Registers.Unset_Mask
              (Register => Registers.LCPLL1_CTL,
               Mask     => LCPLL1_CTL_PLL_ENABLE);
            Registers.Wait_Unset_Mask
              (Register => Registers.LCPLL1_CTL,
               Mask     => LCPLL1_CTL_PLL_LOCK);
         end if;
      end Disable_DPLL0;

      -- Link rate is latched as the PLL enables. 1080 MHz is the 8.64 GHz
      -- VCO, so frequency select means 308.571/432/540/617.143 MHz.
      procedure Enable_DPLL0
      is
      begin
         Registers.Unset_And_Set_Mask
           (Register    => Registers.DPLL_CTRL1,
            Mask_Unset  => DPLL_CTRL1_DPLL0_HDMI_MODE or
                           DPLL_CTRL1_DPLL0_SSC or
                           DPLL_CTRL1_DPLL0_LINK_RATE_MASK,
            Mask_Set    => DPLL_CTRL1_DPLL0_LINK_RATE_1080MHZ or
                           DPLL_CTRL1_DPLL0_OVERRIDE);
         Registers.Posting_Read (Registers.DPLL_CTRL1);
         Registers.Set_Mask
           (Register    => Registers.LCPLL1_CTL,
            Mask        => LCPLL1_CTL_PLL_ENABLE);
         Registers.Wait_Set_Mask
           (Register    => Registers.LCPLL1_CTL,
            Mask        => LCPLL1_CTL_PLL_LOCK);
      end Enable_DPLL0;
   begin
      PCode.Mailbox_Request
        (MBox        => SKL_PCODE_CDCLK_CONTROL,
         Command     => SKL_CDCLK_PREPARE_FOR_CHANGE,
         Reply_Mask  => SKL_CDCLK_READY_FOR_CHANGE,
         Wait_Ready  => True,
         Success     => Success);

      if not Success then
         pragma Debug (Debug.Put_Line
           ("ERROR: PCODE not ready for frequency change."));
         return;
      end if;

      -- Wa Display #1183: skl,kbl,cfl. Same order as skl_set_cdclk().
      -- The register is left holding only the frequency select and the
      -- decimal, which is what i915 compares against.
      declare
         Freq_Select : constant Word32 :=
           (case CDClk is
               when 617_143_000 => CDCLK_CTL_CD_FREQ_SELECT_675MHZ,
               when 540_000_000 => CDCLK_CTL_CD_FREQ_SELECT_540MHZ,
               when 432_000_000 => CDCLK_CTL_CD_FREQ_SELECT_450MHZ,
               when others      => CDCLK_CTL_CD_FREQ_SELECT_337_5MHZ);
         Decimal : constant Word32 := CDCLK_CTL_CD_FREQ_DECIMAL (CDClk);
         Freq_Mask : constant Word32 :=
            CDCLK_CTL_CD_FREQ_SELECT_MASK or CDCLK_CTL_CD_FREQ_DECIMAL_MASK;
         Need_PLL : constant Boolean := not DPLL0_VCO_Is_864;
         CDCLK_CTL : Word32;
      begin
         if Need_PLL then
            Disable_DPLL0;
         end if;

         Registers.Read (Registers.CDCLK_CTL, CDCLK_CTL);
         if Need_PLL then
            CDCLK_CTL := (CDCLK_CTL and not Freq_Mask) or
                         Freq_Select or Decimal;
            Registers.Write (Registers.CDCLK_CTL, CDCLK_CTL);
         end if;

         CDCLK_CTL := CDCLK_CTL or CDCLK_CTL_DIVMUX_CD_OVERRIDE;
         Registers.Write (Registers.CDCLK_CTL, CDCLK_CTL);
         Registers.Posting_Read (Registers.CDCLK_CTL);

         if Need_PLL then
            Enable_DPLL0;
         end if;

         CDCLK_CTL := CDCLK_CTL and not Freq_Mask;
         Registers.Write (Registers.CDCLK_CTL, CDCLK_CTL);
         CDCLK_CTL := CDCLK_CTL or Freq_Select or Decimal;
         Registers.Write (Registers.CDCLK_CTL, CDCLK_CTL);
         CDCLK_CTL := CDCLK_CTL and not CDCLK_CTL_DIVMUX_CD_OVERRIDE;
         Registers.Write (Registers.CDCLK_CTL, CDCLK_CTL);
         Registers.Posting_Read (Registers.CDCLK_CTL);
      end;

      PCode.Mailbox_Write
        (MBox        => SKL_PCODE_CDCLK_CONTROL,
         Command     => (case CDClk is
                           when 617_143_000 => 3,
                           when 540_000_000 => 2,
                           when 432_000_000 => 1,
                           when others      => 0));
      Registers.Set_Mask
        (Register    => Registers.DBUF_CTL_S0,
         Mask        => DBUF_CTL_DBUF_POWER_REQUEST);
      Registers.Wait_Set_Mask
        (Register    => Registers.DBUF_CTL_S0,
         Mask        => DBUF_CTL_DBUF_POWER_STATE);

      Config.CDClk := CDClk;
   end Set_CDClk;

   procedure Get_Raw_Clock (Raw_Clock : out Frequency_Type)
   is
      Freq_24MHz : Boolean;
   begin
      Raw_Clock := Config.Default_RawClk_Freq;
      if Config.Has_Fractional_RawClk then
         Registers.Is_Set_Mask
           (Register => Registers.SFUSE_STRAP,
            Mask     => SFUSE_STRAP_RAW_FREQUENCY,
            Result   => Freq_24MHz);
         if not Freq_24MHz then
            Raw_Clock := 19_200_000;
         end if;
      end if;
   end Get_Raw_Clock;

   procedure Initialize is
   begin
      Registers.Set_Mask
        (Register    => Registers.NDE_RSTWRN_OPT,
         Mask        => NDE_RSTWRN_OPT_RST_PCH_Handshake_En);

      Registers.Wait_Set_Mask
        (Register    => Registers.FUSE_STATUS,
         Mask        => FUSE_STATUS_PG0_DIST_STATUS);
      PD_On (PW1);
      PD_On (MISC_IO);

      -- WaEnableChickenDCPR:skl,bxt,kbl,glk,cfl
      Registers.Set_Mask
        (Register    => Registers.GEN8_CHICKEN_DCPR_1,
         Mask        => 1 * 2 ** 13);

      -- Display WA #0859 WaFbcWakeMemOn:skl,bxt,kbl,glk,cfl
      Registers.Set_Mask
        (Register    => Registers.ARB_CTL,
         Mask        => DISP_FBC_MEMORY_WAKE);

      Get_Cur_CDClk (Config.CDClk);
      Get_Max_CDClk (Config.Max_CDClk);
      -- 308.571 MHz is the 8.64 GHz VCO rate i915 keeps for an eDP 1.4
      -- link. 337.5/675 MHz are the other VCO, and a DC5/DC6 exit does
      -- not restore them.
      Set_CDClk (308_571_000);

      declare  -- avoid aliasing
         Raw_Clock : Frequency_Type;
      begin
         Get_Raw_Clock (Raw_Clock);
         Config.Raw_Clock := Raw_Clock;
      end;

      -- Tell i915 that pre-OS programmed CDCLK (skl_sanitize_cdclk).
      -- Without this, i915 forces the 8.1 GHz VCO minimum (337.5 MHz),
      -- which underruns high-dotclock eDP modes left active across handoff.
      Registers.Write (Registers.SWF_ILK_18, 16#0000_0001#);
   end Initialize;

   procedure Limit_Dotclocks
     (Configs        : in out Pipe_Configs;
      CDClk_Switch   :    out Boolean)
   is
   begin
      Config_Helpers.Limit_Dotclocks (Configs, Config.Max_CDClk);
      CDClk_Switch :=
         Config.CDClk /= Normalize_CDClk
           (Config_Helpers.Highest_Dotclock (Configs));
   end Limit_Dotclocks;

   procedure Update_CDClk (Configs : in out Pipe_Configs)
   is
      New_CDClk : constant Frequency_Type :=
         Config_Helpers.Highest_Dotclock (Configs);
   begin
      Set_CDClk (New_CDClk);
      Config_Helpers.Limit_Dotclocks (Configs, Config.CDClk);
      -- Keep the handoff flag set across CDCLK changes for the final mode.
      Registers.Write (Registers.SWF_ILK_18, 16#0000_0001#);
   end Update_CDClk;

   procedure Power_Set_To (Configs : Pipe_Configs) is
   begin
      for PD in reverse Dynamic_Domain loop
         if not Need_PD (PD, Configs) then
            PD_Off (PD);
         end if;
      end loop;
      for PD in Dynamic_Domain loop
         if Need_PD (PD, Configs) then
            PD_On (PD);
         end if;
      end loop;
   end Power_Set_To;

   procedure Power_Up (Port : Active_Port_Type; Success : out Boolean) is
   begin
      case Port is
         when eDP          => PD_On (DDI_AE);
         when DP1 | HDMI1  => PD_On (PW2); PD_On (DDI_B);
         when DP2 | HDMI2  => PD_On (PW2); PD_On (DDI_C);
         when DP3 | HDMI3  => PD_On (PW2); PD_On (DDI_D);
         when others       => null;
      end case;
      Success := True;
   end Power_Up;

   procedure Power_Up (Old_Configs, New_Configs : Pipe_Configs) is
   begin
      for PD in Dynamic_Domain loop
         if not Need_PD (PD, Old_Configs) and Need_PD (PD, New_Configs) then
            PD_On (PD);
         end if;
      end loop;
   end Power_Up;

   procedure Power_Down (Old_Configs, Tmp_Configs, New_Configs : Pipe_Configs)
   is
   begin
      for PD in reverse Dynamic_Domain loop
         if (Need_PD (PD, Old_Configs) or Need_PD (PD, Tmp_Configs)) and
            not Need_PD (PD, New_Configs)
         then
            PD_Off (PD);
         end if;
      end loop;
   end Power_Down;

end HW.GFX.GMA.Power_And_Clocks;
