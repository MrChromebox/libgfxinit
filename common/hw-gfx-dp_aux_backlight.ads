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

with HW.GFX.DP_Aux_Ch;

private generic

   type T (<>) is limited private;

   with package Aux_Ch is new DP_Aux_Ch (T => T, others => <>);

package HW.GFX.DP_Aux_Backlight is

   procedure On (Port : in T);

   procedure Off (Port : in T);

end HW.GFX.DP_Aux_Backlight;
