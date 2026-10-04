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

package HW.GFX.GMA.SoC.HDMI
is

   -- Has to be called before the DPLL is enabled.
   procedure Prepare
     (Port_Cfg : in Port_Config;
      Pipe     : in Pipe_Index)
   with
      Pre => Port_Cfg.Port in SoC_Port;

   -- Has to be called after the PHY is set up for the pipe.
   procedure On (Port : SoC_Port);

   procedure Off (Port : SoC_Port);
   procedure All_Off;

end HW.GFX.GMA.SoC.HDMI;
