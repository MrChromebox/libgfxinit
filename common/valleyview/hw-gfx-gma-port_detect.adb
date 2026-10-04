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

package body HW.GFX.GMA.Port_Detect
is

   procedure Initialize
   is
   begin
      Config.Valid_Port := (others => False);
   end Initialize;

   procedure Hotplug_Detect (Port : in Active_Port_Type; Detected : out Boolean)
   is
   begin
      Detected := False;
   end Hotplug_Detect;

   procedure Clear_Hotplug_Detect (Port : Active_Port_Type) is null;

   procedure Hotplug_Live (Port : in Active_Port_Type; Live : out Boolean)
   is
      pragma Unreferenced (Port);
   begin
      Live := False;
   end Hotplug_Live;

end HW.GFX.GMA.Port_Detect;
