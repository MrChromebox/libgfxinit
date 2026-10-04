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

package HW.GFX.GMA.SoC.DP
is

   -- Has to be called after the PHY is set up for the pipe.
   procedure Pre_Training
     (Port_Cfg : in     Port_Config;
      Pipe     : in     Pipe_Index)
   with
      Pre => Port_Cfg.Port in SoC_Port;

   -- Has to be called after the panel, if any, is powered.
   procedure Train
     (Port_Cfg : in     Port_Config;
      Success  :    out Boolean)
   with
      Pre => Port_Cfg.Port in SoC_Port;

   -- Make the power sequencer of the pipe lock onto the port, unless
   -- the port is already enabled. The DPLL of the pipe has to run.
   procedure Kick_Power_Sequencer (Port : SoC_Port; Pipe : Pipe_Index);

   procedure Off (Port : SoC_Port);
   procedure All_Off;

end HW.GFX.GMA.SoC.DP;
