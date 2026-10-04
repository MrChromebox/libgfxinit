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

package body HW.GFX.GMA.PLLs
with
   Refined_State => (State => null)
is

   procedure Initialize is null;

   pragma Warnings (GNATprove, Off, "unused variable ""Port_Cfg""",
                    Reason => "Needed for a common interface");
   procedure Alloc
     (Port_Cfg : in     Port_Config;
      PLL      :    out T;
      Success  :    out Boolean)
   is
   begin
      PLL := Invalid;
      Success := False;
   end Alloc;
   pragma Warnings (GNATprove, On, "unused variable ""Port_Cfg""");

   procedure Free (PLL : T) is null;

   procedure All_Off is null;

   function Register_Value (PLL : T) return Word32 is (0);

end HW.GFX.GMA.PLLs;
