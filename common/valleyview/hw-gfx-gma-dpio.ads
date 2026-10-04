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

private package HW.GFX.GMA.DPIO is

   -- PLL and common lane registers are per pipe (DPIO channel of the
   -- DPLL), PCS and TX registers per port (DPIO channel of the port).
   subtype DPIO_Pipe is Pipe_Index range Primary .. Secondary;
   subtype DPIO_Port is GPU_Port range DIGI_B .. DIGI_C;

   subtype N_Range  is Natural range  1 ..   7;
   subtype M1_Range is Natural range  2 ..   3;
   subtype M2_Range is Natural range 11 .. 156;
   subtype P1_Range is Natural range  2 ..   3;
   subtype P2_Range is Natural range  2 ..  20;

   type PLL_Dividers is record
      N  : N_Range;
      M1 : M1_Range;
      M2 : M2_Range;
      P1 : P1_Range;
      P2 : P2_Range;
   end record;

   procedure Prepare_PLL
     (Pipe        : DPIO_Pipe;
      Dividers    : PLL_Dividers;
      Is_DP       : Boolean;
      Low_Rate    : Boolean);

   procedure Pre_PLL_Enable (Port : DPIO_Port);

   procedure Pre_Encoder_Enable (Pipe : DPIO_Pipe; Port : DPIO_Port);

   procedure Set_Signal_Levels
     (Port           : DPIO_Port;
      De_Emphasis    : Word32;
      Pre_Emphasis   : Word32;
      Uniq_Transcale : Word32;
      TX3_De_Emph    : Word32 := 0);

   procedure Set_HDMI_Signal_Levels (Port : DPIO_Port);

   procedure Reset_Lanes (Port : DPIO_Port);

   procedure Wait_Port_Ready (Port : DPIO_Port);

end HW.GFX.GMA.DPIO;
