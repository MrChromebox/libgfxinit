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

with HW.GFX.GMA.Config;

private package HW.GFX.GMA.SoC is

   -- Port D is only available on Braswell.
   subtype SoC_Port is GPU_Port range DIGI_B .. DIGI_D;

   function Last_Port return SoC_Port is
     (if Config.Has_CHV_PHY then DIGI_D else DIGI_C);

   -- Valleyview selects pipe A or B with a single bit in all port
   -- registers, Braswell uses two bit fields in the DP and HDMI ports.
   PORT_PIPE_SELECT_MASK   : constant := 1 * 2 ** 30;
   function PORT_PIPE_SELECT (Pipe : Pipe_Index) return Word32 is
     (if Pipe = Secondary then 1 * 2 ** 30 else 0);

   function DP_PIPE_SELECT (Pipe : Pipe_Index) return Word32 is
     (if Config.Has_CHV_PHY
      then Shift_Left (Word32 (Pipe_Index'Pos (Pipe)), 16)
      else PORT_PIPE_SELECT (Pipe));

   function HDMI_PIPE_SELECT (Pipe : Pipe_Index) return Word32 is
     (if Config.Has_CHV_PHY
      then Shift_Left (Word32 (Pipe_Index'Pos (Pipe)), 24)
      else PORT_PIPE_SELECT (Pipe));

end HW.GFX.GMA.SoC;
