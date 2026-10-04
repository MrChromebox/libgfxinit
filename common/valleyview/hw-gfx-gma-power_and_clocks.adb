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

package body HW.GFX.GMA.Power_And_Clocks is

   procedure Initialize
   is
   begin
      Config.CDClk := Config.Default_CDClk_Freq;
      Config.Max_CDClk := Config.Default_CDClk_Freq;
      Config.Raw_Clock := Config.Default_RawClk_Freq;
   end Initialize;

   procedure Limit_Dotclocks
     (Configs        : in out Pipe_Configs;
      CDClk_Switch   :    out Boolean)
   is
   begin
      Config_Helpers.Limit_Dotclocks (Configs, Config.CDClk * 90 / 100);
      CDClk_Switch := False;
   end Limit_Dotclocks;

   procedure Power_Up (Port : Active_Port_Type; Success : out Boolean) is
   begin
      Success := True;
   end Power_Up;

end HW.GFX.GMA.Power_And_Clocks;
