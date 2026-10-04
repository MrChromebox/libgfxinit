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

with HW.GFX.GMA.IOSF;
with HW.GFX.GMA.Registers;

with HW.Debug;
with GNAT.Source_Info;

package body HW.GFX.GMA.DPIO is

   type Pipe_Regs is array (DPIO_Pipe) of Word32;
   type Port_Regs is array (DPIO_Port) of Word32;

   function PLL_DW (DW : Natural) return Pipe_Regs is
     (Primary   => Word32 (16#8000# + DW * 4),
      Secondary => Word32 (16#8020# + DW * 4));

   VLV_PLL_DW3       : constant Pipe_Regs := PLL_DW (3);
   VLV_PLL_DW5       : constant Pipe_Regs := PLL_DW (5);
   VLV_PLL_DW7       : constant Pipe_Regs := PLL_DW (7);
   VLV_PLL_DW16      : constant Pipe_Regs := PLL_DW (16);
   VLV_PLL_DW17      : constant Pipe_Regs := PLL_DW (17);
   VLV_PLL_DW18      : constant Pipe_Regs := PLL_DW (18);
   VLV_PLL_DW19      : constant Pipe_Regs := PLL_DW (19);
   VLV_REF_DW11      : constant := 16#80ac#;
   VLV_CMN_DW0       : constant := 16#8100#;
   VLV_PCS_DW17_BCAST : constant := 16#c044#;

   function PCS_DW (DW : Natural) return Port_Regs is
     (DIGI_B => Word32 (16#8200# + DW * 4),
      DIGI_C => Word32 (16#8400# + DW * 4));
   function TX_DW (DW : Natural) return Port_Regs is
     (DIGI_B => Word32 (16#8280# + DW * 4),
      DIGI_C => Word32 (16#8480# + DW * 4));

   VLV_PCS_DW0       : constant Port_Regs := PCS_DW (0);
   VLV_PCS_DW1       : constant Port_Regs := PCS_DW (1);
   VLV_PCS_DW8       : constant Port_Regs := PCS_DW (8);
   VLV_PCS_DW9       : constant Port_Regs := PCS_DW (9);
   VLV_PCS_DW11      : constant Port_Regs := PCS_DW (11);
   VLV_PCS_DW12      : constant Port_Regs := PCS_DW (12);
   VLV_PCS_DW14      : constant Port_Regs := PCS_DW (14);
   VLV_PCS_DW23      : constant Port_Regs := PCS_DW (23);
   VLV_TX_DW2        : constant Port_Regs := TX_DW (2);
   VLV_TX_DW3        : constant Port_Regs := TX_DW (3);
   VLV_TX_DW4        : constant Port_Regs := TX_DW (4);
   VLV_TX_DW5        : constant Port_Regs := TX_DW (5);
   VLV_TX_DW11       : constant Port_Regs := TX_DW (11);
   VLV_TX_DW14       : constant Port_Regs := TX_DW (14);
   -- TX_DW4 of lane 3 only, used for the HDMI clock lane
   VLV_TX3_DW4       : constant Port_Regs :=
     (DIGI_B => 16#0690#,
      DIGI_C => 16#2a90#);

   DPIO_S1_DIV_HDMIDP               : constant := 1 * 2 ** 28;
   DPIO_K_DIV_1                     : constant := 1 * 2 ** 24;
   DPIO_ENABLE_CALIBRATION          : constant := 1 * 2 ** 11;

   DPIO_PCS_TX_LANE2_RESET          : constant := 1 * 2 ** 16;
   DPIO_PCS_TX_LANE1_RESET          : constant := 1 * 2 **  7;
   DPIO_PCS_CLK_CRI_RXEB_EIOS_EN    : constant := 1 * 2 ** 22;
   DPIO_PCS_CLK_CRI_RXDIGFILTSG_EN  : constant := 1 * 2 ** 21;
   DPIO_PCS_CLK_DATAWIDTH_8_10      : constant := 1 * 2 **  6;
   DPIO_PCS_CLK_SOFT_RESET          : constant := 1 * 2 **  5;
   DPIO_PCS_USEDCLKCHANNEL          : constant := 1 * 2 ** 21;
   DPIO_PCS_USEDCLKCHANNEL_OVRRIDE  : constant := 1 * 2 ** 20;
   DPIO_TX_OCALINIT_EN              : constant := 1 * 2 ** 31;

   DPLL_PORTB_READY_MASK            : constant := 16#0f#;
   DPLL_PORTC_READY_MASK            : constant := 16#f0#;

   procedure Write (Register : Word32; Value : Word32) is
   begin
      IOSF.Write (IOSF.DPIO, Register, Value);
   end Write;

   procedure Unset_And_Set_Mask (Register, Mask_Unset, Mask_Set : Word32) is
   begin
      IOSF.Unset_And_Set_Mask (IOSF.DPIO, Register, Mask_Unset, Mask_Set);
   end Unset_And_Set_Mask;

   ----------------------------------------------------------------------------

   -- PLL B opamp always calibrates to its maximum of 0x3f.
   -- Force enable it and set it to a reasonable value instead.
   procedure Recalibrate_PLL_B_Opamp is
   begin
      Unset_And_Set_Mask (VLV_PLL_DW17 (Secondary), 16#0000_00ff#, 16#30#);
      Unset_And_Set_Mask (VLV_REF_DW11, 16#ff00_0000#, 16#8c00_0000#);
      Unset_And_Set_Mask (VLV_PLL_DW17 (Secondary), 16#0000_00ff#, 0);
      Unset_And_Set_Mask (VLV_REF_DW11, 16#ff00_0000#, 16#b000_0000#);
   end Recalibrate_PLL_B_Opamp;

   -- i915: vlv_prepare_pll()
   procedure Prepare_PLL
     (Pipe        : DPIO_Pipe;
      Dividers    : PLL_Dividers;
      Is_DP       : Boolean;
      Low_Rate    : Boolean)
   is
      MDiv : constant Word32 :=
         Shift_Left (Word32 (Dividers.P1), 21) or
         Shift_Left (Word32 (Dividers.P2), 16) or
         Shift_Left (Word32 (Dividers.N), 12) or
         Shift_Left (Word32 (Dividers.M1), 8) or
         Word32 (Dividers.M2) or
         DPIO_S1_DIV_HDMIDP or
         DPIO_K_DIV_1;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      if Pipe = Secondary then
         Recalibrate_PLL_B_Opamp;
      end if;

      -- Tx target for periodic Rcomp update
      Write (VLV_PCS_DW17_BCAST, 16#0100_000f#);

      -- Disable target IRef on PLL
      Unset_And_Set_Mask (VLV_PLL_DW16 (Pipe), 16#ff00_0000#, 0);

      -- Disable fast lock
      Write (VLV_CMN_DW0, 16#0610#);

      -- Set idtafcrecal before PLL is enabled
      Write (VLV_PLL_DW3 (Pipe), MDiv);
      Write (VLV_PLL_DW3 (Pipe), MDiv or DPIO_ENABLE_CALIBRATION);

      -- LPF coefficients for RBR / HDMI and HBR
      Write (VLV_PLL_DW18 (Pipe),
             (if Low_Rate then 16#009f_0003# else 16#00d0_000f#));

      -- SSC source for DP, bend source for HDMI
      Write (VLV_PLL_DW5 (Pipe),
             (if Is_DP = (Pipe = Primary)
              then 16#0df4_0000# else 16#0df7_0000#));

      Unset_And_Set_Mask (VLV_PLL_DW7 (Pipe), 16#ffff_00ff#, 16#01c0_0000#);

      Write (VLV_PLL_DW19 (Pipe), 16#8787_1000#);
   end Prepare_PLL;

   ----------------------------------------------------------------------------

   -- i915: vlv_phy_pre_pll_enable()
   procedure Pre_PLL_Enable (Port : DPIO_Port) is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      -- Program Tx lane resets to default
      Write (VLV_PCS_DW0 (Port),
             DPIO_PCS_TX_LANE2_RESET or DPIO_PCS_TX_LANE1_RESET);
      Write (VLV_PCS_DW1 (Port),
             DPIO_PCS_CLK_CRI_RXEB_EIOS_EN or
             DPIO_PCS_CLK_CRI_RXDIGFILTSG_EN or
             DPIO_PCS_CLK_DATAWIDTH_8_10 or
             DPIO_PCS_CLK_SOFT_RESET);

      -- Fix up inter-pair skew failure
      Write (VLV_PCS_DW12 (Port), 16#0075_0f00#);
      Write (VLV_TX_DW11 (Port), 16#0000_1500#);
      Write (VLV_TX_DW14 (Port), 16#4040_0000#);
   end Pre_PLL_Enable;

   -- i915: vlv_phy_pre_encoder_enable()
   procedure Pre_Encoder_Enable (Pipe : DPIO_Pipe; Port : DPIO_Port) is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      -- Enable clock channels for this port
      Write (VLV_PCS_DW8 (Port),
             DPIO_PCS_USEDCLKCHANNEL_OVRRIDE or
             (if Pipe = Secondary then DPIO_PCS_USEDCLKCHANNEL else 0) or
             16#c4#);

      -- Program lane clock
      Write (VLV_PCS_DW14 (Port), 16#0076_0018#);
      Write (VLV_PCS_DW23 (Port), 16#0040_0888#);
   end Pre_Encoder_Enable;

   -- i915: vlv_set_phy_signal_level()
   procedure Set_Signal_Levels
     (Port           : DPIO_Port;
      De_Emphasis    : Word32;
      Pre_Emphasis   : Word32;
      Uniq_Transcale : Word32;
      TX3_De_Emph    : Word32 := 0)
   is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Write (VLV_TX_DW5 (Port), 0);
      Write (VLV_TX_DW4 (Port), De_Emphasis);
      Write (VLV_TX_DW2 (Port), Uniq_Transcale);
      Write (VLV_TX_DW3 (Port), 16#0c78_2040#);
      if TX3_De_Emph /= 0 then
         Write (VLV_TX3_DW4 (Port), TX3_De_Emph);
      end if;
      Write (VLV_PCS_DW11 (Port), 16#0003_0000#);
      Write (VLV_PCS_DW9 (Port), Pre_Emphasis);
      Write (VLV_TX_DW5 (Port), DPIO_TX_OCALINIT_EN);
   end Set_Signal_Levels;

   -- i915: vlv_hdmi_pre_enable(), 1.0V swing with 3.5dB de-emphasis
   -- and no de-emphasis on the clock lane
   procedure Set_HDMI_Signal_Levels (Port : DPIO_Port) is
   begin
      Set_Signal_Levels
        (Port           => Port,
         De_Emphasis    => 16#2b24_5f5f#,
         Pre_Emphasis   => 16#0000_2000#,
         Uniq_Transcale => 16#5578_b83a#,
         TX3_De_Emph    => 16#2b24_7878#);
   end Set_HDMI_Signal_Levels;

   -- i915: vlv_phy_reset_lanes()
   procedure Reset_Lanes (Port : DPIO_Port) is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Write (VLV_PCS_DW0 (Port), 0);
      Write (VLV_PCS_DW1 (Port), 16#00e0_0060#);
   end Reset_Lanes;

   -- i915: vlv_wait_port_ready()
   procedure Wait_Port_Ready (Port : DPIO_Port) is
   begin
      Registers.Wait_Unset_Mask
        (Register => Registers.GMCH_DPLL_A,
         Mask     => (if Port = DIGI_B
                      then DPLL_PORTB_READY_MASK
                      else DPLL_PORTC_READY_MASK),
         TOut_MS  => 1_000,
         Verbose  => True);
   end Wait_Port_Ready;

end HW.GFX.GMA.DPIO;
