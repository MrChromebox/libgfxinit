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

-- The DPIO PHYs of Braswell: PHY0 with two channels for ports B and C,
-- PHY1 with a single channel for port D. The PLL and common lane
-- registers are per pipe (DPIO channel of the DPLL), the PCS and TX
-- registers per port (DPIO channel of the port).
private package HW.GFX.GMA.DPIO_CHV is

   type PHY_Type is (PHY0, PHY1);
   type Channel_Type is (CH0, CH1);

   subtype CHV_Port is GPU_Port range DIGI_B .. DIGI_D;

   function Port_PHY (Port : CHV_Port) return PHY_Type is
     (if Port = DIGI_D then PHY1 else PHY0);
   function Port_Channel (Port : CHV_Port) return Channel_Type is
     (if Port = DIGI_C then CH1 else CH0);
   function Pipe_PHY (Pipe : Pipe_Index) return PHY_Type is
     (if Pipe = Tertiary then PHY1 else PHY0);
   function Pipe_Channel (Pipe : Pipe_Index) return Channel_Type is
     (if Pipe = Secondary then CH1 else CH0);

   ----------------------------------------------------------------------------

   -- DISPLAY_PHY_CONTROL is write-only, the user has to keep a copy.

   PHY_Control_Initial : constant Word32 := 16#0500_07fc#;

   function PHY_CH_POWER_DOWN_OVRD_EN
     (PHY : PHY_Type; CH : Channel_Type) return Word32 is
     (Shift_Left (1, 27 + 2 * PHY_Type'Pos (PHY) + Channel_Type'Pos (CH)));

   function PHY_CH_POWER_DOWN_OVRD
     (Mask : Word32; PHY : PHY_Type; CH : Channel_Type) return Word32 is
     (Shift_Left
        (Value  => Mask and 16#f#,
         Amount => 11 + 8 * PHY_Type'Pos (PHY) + 4 * Channel_Type'Pos (CH)));

   function PHY_COM_LANE_RESET_DEASSERT (PHY : PHY_Type) return Word32 is
     (Shift_Left (1, PHY_Type'Pos (PHY)));

   -- Lanes not used by a port, which are powered down.
   function Unused_Lane_Mask (Lane_Count : DP_Lane_Count) return Word32 is
     ((not (Shift_Left (1, Natural (Lane_Count_As_Integer (Lane_Count))) - 1))
      and 16#f#);

   -- Has to be called after the common lane power well of the PHY
   -- was enabled, before the common lane reset is deasserted.
   procedure Common_Lane_Init (PHY : PHY_Type);

   -- Waits for the common lane of a channel to power up, after lanes
   -- of the channel were powered through DISPLAY_PHY_CONTROL.
   procedure Wait_Common_Lane_Powered (PHY : PHY_Type; CH : Channel_Type);

   ----------------------------------------------------------------------------

   -- All frequencies in kHz, M2 is a 22-bit binary fixed-point number.
   subtype P1_Range is Natural range 2 .. 4;
   subtype P2_Range is Natural range 1 .. 14;
   subtype M2_Range is Int64 range 24 * 2 ** 22 .. 175 * 2 ** 22;

   type PLL_Dividers is record
      P1 : P1_Range;
      P2 : P2_Range;
      M2 : M2_Range;
   end record;

   procedure Prepare_PLL
     (Pipe     : Pipe_Index;
      Dividers : PLL_Dividers;
      VCO      : Int64);

   -- Enables or disables the 10-bit clock to the display controller.
   procedure Set_DCLKP (Pipe : Pipe_Index; Enable : Boolean);

   ----------------------------------------------------------------------------

   procedure Pre_PLL_Enable
     (Pipe        : Pipe_Index;
      Port        : CHV_Port;
      Lane_Count  : DP_Lane_Count);

   procedure Pre_Encoder_Enable
     (Port        : CHV_Port;
      Lane_Count  : DP_Lane_Count;
      Port_Clock  : Int64);

   procedure Post_PLL_Disable (Pipe : Pipe_Index; Port : CHV_Port);

   procedure Data_Lane_Soft_Reset
     (Port        : CHV_Port;
      Lane_Count  : DP_Lane_Count;
      Reset       : Boolean);

   procedure Set_Signal_Levels
     (Port              : CHV_Port;
      Lane_Count        : DP_Lane_Count;
      De_Emphasis       : Word32;
      Margin            : Word32;
      Uniq_Trans_Scale  : Boolean);

   procedure Set_HDMI_Signal_Levels (Port : CHV_Port);

   procedure Wait_Port_Ready (Port : CHV_Port; Unused_Lanes : Word32);

end HW.GFX.GMA.DPIO_CHV;
