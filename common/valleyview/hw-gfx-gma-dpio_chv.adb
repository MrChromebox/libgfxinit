--
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

with HW.GFX.GMA.IOSF;
with HW.GFX.GMA.Registers;

with HW.Debug;
with GNAT.Source_Info;

package body HW.GFX.GMA.DPIO_CHV is

   IOSF_Unit : constant array (PHY_Type) of IOSF.Unit_Type :=
     (PHY0 => IOSF.DPIO_2,
      PHY1 => IOSF.DPIO);

   subtype Lane_Index is Natural range 0 .. 3;
   subtype Spline_Index is Natural range 0 .. 1;

   function CMN (CL : Channel_Type; DW : Natural) return Word32 is
     (Word32 (16#8100# - Channel_Type'Pos (CL) * 16#80# + DW * 4));
   function PLL (CH : Channel_Type; DW : Natural) return Word32 is
     (Word32 (16#8000# + Channel_Type'Pos (CH) * 16#180# + DW * 4));
   function PCS (CH : Channel_Type; Spline : Spline_Index; DW : Natural)
      return Word32 is
     (Word32 (16#0200# + Channel_Type'Pos (CH) * 16#2400# +
              Spline * 16#200# + DW * 4));
   function TX (CH : Channel_Type; Lane : Lane_Index; DW : Natural)
      return Word32 is
     (Word32 (16#0080# + Channel_Type'Pos (CH) * 16#2400# +
              Lane * 16#200# + DW * 4));

   -- Common lane registers that differ between the channels
   function CMN_DW13 (CH : Channel_Type) return Word32 is
     (if CH = CH0 then CMN (CH0, 13) else CMN (CH1, 0));
   function CMN_DW14 (CH : Channel_Type) return Word32 is
     (if CH = CH0 then CMN (CH0, 14) else CMN (CH1, 1));
   function CMN_DW19 (CH : Channel_Type) return Word32 is
     (if CH = CH0 then CMN (CH0, 19) else CMN (CH1, 6));

   CMN_DW5_CH0                      : constant Word32 := CMN (CH0, 5);
   CMN_DW1_CH1                      : constant Word32 := CMN (CH1, 1);
   CMN_DW6_CH1                      : constant Word32 := CMN (CH1, 6);
   CMN_DW28                         : constant Word32 := CMN (CH0, 28);
   CMN_DW30                         : constant Word32 := CMN (CH0, 30);

   CHV_BUFLEFTENA1_MASK             : constant := 3 * 2 ** 22;
   CHV_BUFLEFTENA1_FORCE            : constant := 3 * 2 ** 22;
   CHV_BUFRIGHTENA1_MASK            : constant := 3 * 2 ** 20;
   CHV_BUFRIGHTENA1_FORCE           : constant := 3 * 2 ** 20;
   CHV_BUFRIGHTENA2_MASK            : constant := 3 * 2 ** 19;
   CHV_BUFRIGHTENA2_FORCE           : constant := 3 * 2 ** 19;
   CHV_BUFLEFTENA2_MASK             : constant := 3 * 2 ** 17;
   CHV_BUFLEFTENA2_FORCE            : constant := 3 * 2 ** 17;
   DPIO_AFC_RECAL                   : constant := 1 * 2 ** 14;
   DPIO_DCLKP_EN                    : constant := 1 * 2 ** 13;
   CHV_CMN_USEDCLKCHANNEL           : constant := 1 * 2 ** 13;
   DPIO_DYNPWRDOWNEN_CH1            : constant := 1 * 2 ** 28;
   DPIO_CL1POWERDOWNEN              : constant := 1 * 2 ** 23;
   DPIO_DYNPWRDOWNEN_CH0            : constant := 1 * 2 ** 22;
   DPIO_SUS_CLK_CONFIG_GATE_CLKREQ  : constant := 3 * 2 **  0;
   DPIO_CL2_LDOFUSE_PWRENB          : constant := 1 * 2 **  6;

   DPIO_CHV_S1_DIV_SHIFT            : constant := 21;
   DPIO_CHV_P1_DIV_SHIFT            : constant := 13;
   DPIO_CHV_P2_DIV_SHIFT            : constant :=  8;
   DPIO_CHV_K_DIV_SHIFT             : constant :=  4;
   DPIO_CHV_N_DIV_SHIFT             : constant :=  8;
   DPIO_CHV_FRAC_DIV_EN             : constant := 1 * 2 ** 16;
   DPIO_CHV_FEEDFWD_GAIN_MASK       : constant := 16#f# * 2 ** 0;
   DPIO_CHV_INT_LOCK_THRESHOLD_MASK : constant := 7 * 2 ** 1;
   DPIO_CHV_INT_LOCK_THRESHOLD_COARSE : constant := 1 * 2 ** 0;
   DPIO_CHV_GAIN_CTRL_SHIFT         : constant := 16;
   DPIO_CHV_INT_COEFF_SHIFT         : constant :=  8;
   DPIO_CHV_TDC_TARGET_CNT_MASK     : constant := 16#3ff# * 2 ** 0;

   DPIO_PCS_TX_LANE2_RESET          : constant := 1 * 2 ** 16;
   DPIO_PCS_TX_LANE1_RESET          : constant := 1 * 2 **  7;
   CHV_PCS_REQ_SOFTRESET_EN         : constant := 1 * 2 ** 23;
   DPIO_PCS_CLK_SOFT_RESET          : constant := 1 * 2 **  5;
   DPIO_PCS_USEDCLKCHANNEL          : constant := 1 * 2 ** 21;
   DPIO_PCS_USEDCLKCHANNEL_OVRRIDE  : constant := 1 * 2 ** 20;
   DPIO_PCS_TX2MARGIN_MASK          : constant := 7 * 2 ** 13;
   DPIO_PCS_TX1MARGIN_MASK          : constant := 7 * 2 ** 10;
   DPIO_PCS_SWING_CALC_TX1_TX3      : constant := 1 * 2 ** 31;
   DPIO_PCS_SWING_CALC_TX0_TX2      : constant := 1 * 2 ** 30;
   DPIO_PCS_TX2DEEMP_MASK           : constant := 16#f# * 2 ** 24;
   DPIO_PCS_TX1DEEMP_MASK           : constant := 16#f# * 2 ** 16;
   DPIO_TX2_STAGGER_MASK_SHIFT      : constant := 24;
   DPIO_LANEDESKEW_STRAP_OVRD       : constant := 1 * 2 **  3;
   DPIO_TX2_STAGGER_MULT_SHIFT      : constant := 20;
   DPIO_TX1_STAGGER_MULT_SHIFT      : constant := 16;
   DPIO_TX1_STAGGER_MASK_SHIFT      : constant :=  8;
   DPIO_LANESTAGGER_STRAP_OVRD      : constant := 1 * 2 **  6;

   DPIO_SWING_MARGIN000_MASK        : constant := 16#ff# * 2 ** 16;
   DPIO_UNIQ_TRANS_SCALE_MASK       : constant := 16#ff# * 2 **  8;
   DPIO_UNIQ_TRANS_SCALE_DEFAULT    : constant := 16#9a# * 2 **  8;
   DPIO_TX_UNIQ_TRANS_SCALE_EN      : constant := 1 * 2 ** 27;
   DPIO_SWING_DEEMPH9P5_MASK        : constant := 16#ff# * 2 ** 24;
   DPIO_UPAR                        : constant := 1 * 2 ** 30;

   PHY_POWERGOOD : constant array (PHY_Type) of Word32 :=
     (PHY0 => 1 * 2 ** 31,
      PHY1 => 1 * 2 ** 30);

   DPLL_PORTB_READY_MASK            : constant := 16#0f#;
   DPLL_PORTC_READY_MASK            : constant := 16#f0#;
   DPLL_PORTD_READY_MASK            : constant := 16#0f#;

   ----------------------------------------------------------------------------

   procedure Write (PHY : PHY_Type; Register : Word32; Value : Word32) is
   begin
      IOSF.Write (IOSF_Unit (PHY), Register, Value);
   end Write;

   procedure Unset_And_Set_Mask
     (PHY         : PHY_Type;
      Register    : Word32;
      Mask_Unset  : Word32;
      Mask_Set    : Word32) is
   begin
      IOSF.Unset_And_Set_Mask
        (IOSF_Unit (PHY), Register, Mask_Unset, Mask_Set);
   end Unset_And_Set_Mask;

   -- Applies the mask operation to the PCS register of the first two
   -- lanes and, if more than two lanes are used, to that of the others.
   procedure PCS_Unset_And_Set_Mask
     (Port        : CHV_Port;
      Lane_Count  : DP_Lane_Count;
      DW          : Natural;
      Mask_Unset  : Word32;
      Mask_Set    : Word32)
   is
   begin
      for Spline in Spline_Index range
         0 .. (if Lane_Count = DP_Lane_Count_4 then 1 else 0)
      loop
         Unset_And_Set_Mask
           (PHY         => Port_PHY (Port),
            Register    => PCS (Port_Channel (Port), Spline, DW),
            Mask_Unset  => Mask_Unset,
            Mask_Set    => Mask_Set);
      end loop;
   end PCS_Unset_And_Set_Mask;

   ----------------------------------------------------------------------------

   -- i915: chv_dpio_cmn_power_well_enable()
   procedure Common_Lane_Init (PHY : PHY_Type) is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity & ": " &
                                    PHY_Type'Image (PHY)));

      Registers.Wait_Set_Mask
        (Register => Registers.CHV_DISPLAY_PHY_STATUS,
         Mask     => PHY_POWERGOOD (PHY),
         TOut_MS  => 1,
         Verbose  => True);

      -- Enable dynamic power down
      Unset_And_Set_Mask
        (PHY         => PHY,
         Register    => CMN_DW28,
         Mask_Unset  => 0,
         Mask_Set    => DPIO_DYNPWRDOWNEN_CH0 or DPIO_CL1POWERDOWNEN or
                        DPIO_SUS_CLK_CONFIG_GATE_CLKREQ);

      if PHY = PHY0 then
         Unset_And_Set_Mask (PHY, CMN_DW6_CH1, 0, DPIO_DYNPWRDOWNEN_CH1);
      else
         -- Force the non-existing second common lane off
         Unset_And_Set_Mask (PHY, CMN_DW30, 0, DPIO_CL2_LDOFUSE_PWRENB);
      end if;
   end Common_Lane_Init;

   procedure Wait_Common_Lane_Powered (PHY : PHY_Type; CH : Channel_Type)
   is
      PHY_STATUS_CMN_LDO : constant Word32 := Shift_Left
        (1, 6 - (6 * PHY_Type'Pos (PHY) + 3 * Channel_Type'Pos (CH)));
   begin
      -- The PHY may be busy with some calibration, according to i915.
      Registers.Wait_Unset_Mask
        (Register => Registers.CHV_DISPLAY_PHY_STATUS,
         Mask     => PHY_STATUS_CMN_LDO,
         TOut_MS  => 10,
         Verbose  => True);
   end Wait_Common_Lane_Powered;

   ----------------------------------------------------------------------------

   -- i915: chv_prepare_pll()
   procedure Prepare_PLL
     (Pipe     : Pipe_Index;
      Dividers : PLL_Dividers;
      VCO      : Int64)
   is
      PHY : constant PHY_Type := Pipe_PHY (Pipe);
      CH : constant Channel_Type := Pipe_Channel (Pipe);

      M2_Int : constant Word32 := Word32 (Dividers.M2 / 2 ** 22);
      M2_Frac : constant Word32 := Word32 (Dividers.M2 mod 2 ** 22);

      Prop_Coeff, Int_Coeff, Gain_Ctrl, Tribuf_Calcntr : Word32;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      -- P1 and P2 dividers
      Write
        (PHY      => PHY,
         Register => CMN_DW13 (CH),
         Value    =>
            Shift_Left (5, DPIO_CHV_S1_DIV_SHIFT) or
            Shift_Left (Word32 (Dividers.P1), DPIO_CHV_P1_DIV_SHIFT) or
            Shift_Left (Word32 (Dividers.P2), DPIO_CHV_P2_DIV_SHIFT) or
            Shift_Left (1, DPIO_CHV_K_DIV_SHIFT));

      -- Feedback post-divider M2, N = 1 and M1 = 2 (encoded as 0)
      Write (PHY, PLL (CH, 0), M2_Int);
      Write (PHY, PLL (CH, 1), Shift_Left (1, DPIO_CHV_N_DIV_SHIFT));
      Write (PHY, PLL (CH, 2), M2_Frac);

      -- M2 fraction division enable
      Unset_And_Set_Mask
        (PHY         => PHY,
         Register    => PLL (CH, 3),
         Mask_Unset  => DPIO_CHV_FEEDFWD_GAIN_MASK or DPIO_CHV_FRAC_DIV_EN,
         Mask_Set    =>
            2 or (if M2_Frac /= 0 then DPIO_CHV_FRAC_DIV_EN else 0));

      -- Digital lock detect threshold
      Unset_And_Set_Mask
        (PHY         => PHY,
         Register    => PLL (CH, 9),
         Mask_Unset  => DPIO_CHV_INT_LOCK_THRESHOLD_MASK or
                        DPIO_CHV_INT_LOCK_THRESHOLD_COARSE,
         Mask_Set    => Shift_Left (5, 1) or
                        (if M2_Frac = 0
                         then DPIO_CHV_INT_LOCK_THRESHOLD_COARSE else 0));

      -- Loop filter
      if VCO = 5_400_000 then
         Prop_Coeff := 16#3#;
         Int_Coeff := 16#8#;
         Gain_Ctrl := 16#1#;
         Tribuf_Calcntr := 16#9#;
      elsif VCO <= 6_200_000 then
         Prop_Coeff := 16#5#;
         Int_Coeff := 16#b#;
         Gain_Ctrl := 16#3#;
         Tribuf_Calcntr := 16#9#;
      else
         Prop_Coeff := 16#4#;
         Int_Coeff := 16#9#;
         Gain_Ctrl := 16#3#;
         Tribuf_Calcntr := 16#8#;
      end if;
      Write
        (PHY      => PHY,
         Register => PLL (CH, 6),
         Value    => Prop_Coeff or
                     Shift_Left (Int_Coeff, DPIO_CHV_INT_COEFF_SHIFT) or
                     Shift_Left (Gain_Ctrl, DPIO_CHV_GAIN_CTRL_SHIFT));
      Unset_And_Set_Mask
        (PHY         => PHY,
         Register    => PLL (CH, 8),
         Mask_Unset  => DPIO_CHV_TDC_TARGET_CNT_MASK,
         Mask_Set    => Tribuf_Calcntr);

      -- AFC recalibration
      Unset_And_Set_Mask (PHY, CMN_DW14 (CH), 0, DPIO_AFC_RECAL);
   end Prepare_PLL;

   procedure Set_DCLKP (Pipe : Pipe_Index; Enable : Boolean) is
   begin
      Unset_And_Set_Mask
        (PHY         => Pipe_PHY (Pipe),
         Register    => CMN_DW14 (Pipe_Channel (Pipe)),
         Mask_Unset  => (if Enable then 0 else DPIO_DCLKP_EN),
         Mask_Set    => (if Enable then DPIO_DCLKP_EN else 0));
   end Set_DCLKP;

   ----------------------------------------------------------------------------

   -- i915: __chv_data_lane_soft_reset()
   procedure Data_Lane_Soft_Reset
     (Port        : CHV_Port;
      Lane_Count  : DP_Lane_Count;
      Reset       : Boolean)
   is
      Lane_Resets : constant Word32 :=
         DPIO_PCS_TX_LANE2_RESET or DPIO_PCS_TX_LANE1_RESET;
   begin
      PCS_Unset_And_Set_Mask
        (Port        => Port,
         Lane_Count  => Lane_Count,
         DW          => 0,
         Mask_Unset  => (if Reset then Lane_Resets else 0),
         Mask_Set    => (if Reset then 0 else Lane_Resets));
      PCS_Unset_And_Set_Mask
        (Port        => Port,
         Lane_Count  => Lane_Count,
         DW          => 1,
         Mask_Unset  => (if Reset then DPIO_PCS_CLK_SOFT_RESET else 0),
         Mask_Set    => CHV_PCS_REQ_SOFTRESET_EN or
                        (if Reset then 0 else DPIO_PCS_CLK_SOFT_RESET));
   end Data_Lane_Soft_Reset;

   -- i915: chv_phy_pre_pll_enable(), without the lane power gating
   procedure Pre_PLL_Enable
     (Pipe        : Pipe_Index;
      Port        : CHV_Port;
      Lane_Count  : DP_Lane_Count)
   is
      PHY : constant PHY_Type := Port_PHY (Port);
      CH : constant Channel_Type := Port_Channel (Port);
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Data_Lane_Soft_Reset (Port, Lane_Count, Reset => True);

      -- Left/right clock distribution
      if Pipe /= Secondary then
         Unset_And_Set_Mask
           (PHY         => PHY,
            Register    => CMN_DW5_CH0,
            Mask_Unset  => CHV_BUFLEFTENA1_MASK or CHV_BUFRIGHTENA1_MASK,
            Mask_Set    => (if CH = CH0
                            then CHV_BUFLEFTENA1_FORCE
                            else CHV_BUFRIGHTENA1_FORCE));
      else
         Unset_And_Set_Mask
           (PHY         => PHY,
            Register    => CMN_DW1_CH1,
            Mask_Unset  => CHV_BUFLEFTENA2_MASK or CHV_BUFRIGHTENA2_MASK,
            Mask_Set    => (if CH = CH0
                            then CHV_BUFLEFTENA2_FORCE
                            else CHV_BUFRIGHTENA2_FORCE));
      end if;

      -- Clock channel usage
      PCS_Unset_And_Set_Mask
        (Port        => Port,
         Lane_Count  => Lane_Count,
         DW          => 8,
         Mask_Unset  => DPIO_PCS_USEDCLKCHANNEL,
         Mask_Set    => DPIO_PCS_USEDCLKCHANNEL_OVRRIDE or
                        (if Pipe = Secondary
                         then DPIO_PCS_USEDCLKCHANNEL else 0));

      -- The common lane is picked by the port here, not by the pipe.
      Unset_And_Set_Mask
        (PHY         => PHY,
         Register    => CMN_DW19 (CH),
         Mask_Unset  => CHV_CMN_USEDCLKCHANNEL,
         Mask_Set    => (if Pipe = Secondary
                         then CHV_CMN_USEDCLKCHANNEL else 0));
   end Pre_PLL_Enable;

   -- i915: chv_phy_pre_encoder_enable()
   procedure Pre_Encoder_Enable
     (Port        : CHV_Port;
      Lane_Count  : DP_Lane_Count;
      Port_Clock  : Int64)
   is
      PHY : constant PHY_Type := Port_PHY (Port);
      CH : constant Channel_Type := Port_Channel (Port);
      Lanes : constant Positive :=
         Positive (Lane_Count_As_Integer (Lane_Count));

      Stagger : constant Word32 :=
        (if    Port_Clock > 270_000 then 16#18#
         elsif Port_Clock > 135_000 then 16#0d#
         elsif Port_Clock >  67_500 then 16#07#
         elsif Port_Clock >  33_750 then 16#04#
         else                            16#02#);

      function Stagger_Value (TX1_Mult, TX2_Mult : Word32) return Word32 is
        (Stagger or DPIO_LANESTAGGER_STRAP_OVRD or
         Shift_Left (16#1f#, DPIO_TX1_STAGGER_MASK_SHIFT) or
         Shift_Left (TX1_Mult, DPIO_TX1_STAGGER_MULT_SHIFT) or
         Shift_Left (TX2_Mult, DPIO_TX2_STAGGER_MULT_SHIFT));
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      -- Allow hardware to manage TX FIFO reset source
      PCS_Unset_And_Set_Mask
        (Port, Lane_Count, 11, DPIO_LANEDESKEW_STRAP_OVRD, 0);

      -- TX lane latency optimal setting
      for Lane in Lane_Index range 0 .. Lanes - 1 loop
         Write
           (PHY      => PHY,
            Register => TX (CH, Lane, 14),
            Value    => (if Lanes = 1 or Lane = 1 then 0 else DPIO_UPAR));
      end loop;

      -- Data lane stagger
      PCS_Unset_And_Set_Mask
        (Port        => Port,
         Lane_Count  => Lane_Count,
         DW          => 11,
         Mask_Unset  => 0,
         Mask_Set    => Shift_Left (16#1f#, DPIO_TX2_STAGGER_MASK_SHIFT));
      Write (PHY, PCS (CH, 0, 12), Stagger_Value (6, 0));
      if Lane_Count = DP_Lane_Count_4 then
         Write (PHY, PCS (CH, 1, 12), Stagger_Value (7, 5));
      end if;

      Data_Lane_Soft_Reset (Port, Lane_Count, Reset => False);
   end Pre_Encoder_Enable;

   -- i915: chv_phy_post_pll_disable(), without the lane power gating
   procedure Post_PLL_Disable (Pipe : Pipe_Index; Port : CHV_Port) is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      if Pipe /= Secondary then
         Unset_And_Set_Mask
           (PHY         => Port_PHY (Port),
            Register    => CMN_DW5_CH0,
            Mask_Unset  => CHV_BUFLEFTENA1_MASK or CHV_BUFRIGHTENA1_MASK,
            Mask_Set    => 0);
      else
         Unset_And_Set_Mask
           (PHY         => Port_PHY (Port),
            Register    => CMN_DW1_CH1,
            Mask_Unset  => CHV_BUFLEFTENA2_MASK or CHV_BUFRIGHTENA2_MASK,
            Mask_Set    => 0);
      end if;
   end Post_PLL_Disable;

   ----------------------------------------------------------------------------

   -- i915: chv_set_phy_signal_level()
   procedure Set_Signal_Levels
     (Port              : CHV_Port;
      Lane_Count        : DP_Lane_Count;
      De_Emphasis       : Word32;
      Margin            : Word32;
      Uniq_Trans_Scale  : Boolean)
   is
      PHY : constant PHY_Type := Port_PHY (Port);
      CH : constant Channel_Type := Port_Channel (Port);
      Lanes : constant Positive :=
         Positive (Lane_Count_As_Integer (Lane_Count));
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      -- Clear calc init
      PCS_Unset_And_Set_Mask
        (Port        => Port,
         Lane_Count  => Lane_Count,
         DW          => 10,
         Mask_Unset  => DPIO_PCS_SWING_CALC_TX0_TX2 or
                        DPIO_PCS_SWING_CALC_TX1_TX3 or
                        DPIO_PCS_TX1DEEMP_MASK or DPIO_PCS_TX2DEEMP_MASK,
         Mask_Set    => 0);
      PCS_Unset_And_Set_Mask
        (Port        => Port,
         Lane_Count  => Lane_Count,
         DW          => 9,
         Mask_Unset  => DPIO_PCS_TX1MARGIN_MASK or DPIO_PCS_TX2MARGIN_MASK,
         Mask_Set    => 0);

      for Lane in Lane_Index range 0 .. Lanes - 1 loop
         Unset_And_Set_Mask
           (PHY         => PHY,
            Register    => TX (CH, Lane, 4),
            Mask_Unset  => DPIO_SWING_DEEMPH9P5_MASK,
            Mask_Set    => Shift_Left (De_Emphasis and 16#ff#, 24));
      end loop;

      -- The unique transition scale is always programmed, as it
      -- matters even when disabled, according to i915.
      for Lane in Lane_Index range 0 .. Lanes - 1 loop
         Unset_And_Set_Mask
           (PHY         => PHY,
            Register    => TX (CH, Lane, 2),
            Mask_Unset  => DPIO_SWING_MARGIN000_MASK or
                           DPIO_UNIQ_TRANS_SCALE_MASK,
            Mask_Set    => Shift_Left (Margin and 16#ff#, 16) or
                           DPIO_UNIQ_TRANS_SCALE_DEFAULT);
      end loop;

      for Lane in Lane_Index range 0 .. Lanes - 1 loop
         Unset_And_Set_Mask
           (PHY         => PHY,
            Register    => TX (CH, Lane, 3),
            Mask_Unset  => DPIO_TX_UNIQ_TRANS_SCALE_EN,
            Mask_Set    => (if Uniq_Trans_Scale
                            then DPIO_TX_UNIQ_TRANS_SCALE_EN else 0));
      end loop;

      -- Start swing calculation
      PCS_Unset_And_Set_Mask
        (Port        => Port,
         Lane_Count  => Lane_Count,
         DW          => 10,
         Mask_Unset  => 0,
         Mask_Set    => DPIO_PCS_SWING_CALC_TX0_TX2 or
                        DPIO_PCS_SWING_CALC_TX1_TX3);
   end Set_Signal_Levels;

   -- i915: chv_hdmi_pre_enable(), 800mV with 0dB de-emphasis
   procedure Set_HDMI_Signal_Levels (Port : CHV_Port) is
   begin
      Set_Signal_Levels
        (Port              => Port,
         Lane_Count        => DP_Lane_Count_4,
         De_Emphasis       => 128,
         Margin            => 102,
         Uniq_Trans_Scale  => False);
   end Set_HDMI_Signal_Levels;

   -- i915: vlv_wait_port_ready()
   procedure Wait_Port_Ready (Port : CHV_Port; Unused_Lanes : Word32) is
   begin
      if Port = DIGI_D then
         Registers.Wait
           (Register => Registers.CHV_DPIO_PHY_STATUS,
            Mask     => DPLL_PORTD_READY_MASK,
            Value    => Unused_Lanes and DPLL_PORTD_READY_MASK,
            TOut_MS  => 1_000,
            Verbose  => True);
      else
         Registers.Wait
           (Register => Registers.GMCH_DPLL_A,
            Mask     => (if Port = DIGI_B
                         then DPLL_PORTB_READY_MASK
                         else DPLL_PORTC_READY_MASK),
            Value    => (if Port = DIGI_B
                         then Unused_Lanes and DPLL_PORTB_READY_MASK
                         else Shift_Left (Unused_Lanes, 4) and
                              DPLL_PORTC_READY_MASK),
            TOut_MS  => 1_000,
            Verbose  => True);
      end if;
   end Wait_Port_Ready;

end HW.GFX.GMA.DPIO_CHV;
