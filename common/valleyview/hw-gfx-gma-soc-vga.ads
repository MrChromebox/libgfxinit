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

package HW.GFX.GMA.SoC.VGA
is

   -- The DAC may be fused off, then the enable bit doesn't stick.
   procedure Detect (Present : out Boolean);

   -- Has to be called after the pipe is enabled.
   procedure On
     (Pipe : in Pipe_Index;
      Mode : in Mode_Type);

   procedure Off;

end HW.GFX.GMA.SoC.VGA;
