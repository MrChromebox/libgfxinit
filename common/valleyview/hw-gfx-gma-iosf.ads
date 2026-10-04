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

private package HW.GFX.GMA.IOSF is

   type Unit_Type is (CCK, CCU, PUnit, DPIO);

   procedure Read
     (Unit     : in     Unit_Type;
      Register : in     Word32;
      Value    :    out Word32);

   procedure Write
     (Unit     : in     Unit_Type;
      Register : in     Word32;
      Value    : in     Word32);

   procedure Unset_And_Set_Mask
     (Unit        : in     Unit_Type;
      Register    : in     Word32;
      Mask_Unset  : in     Word32;
      Mask_Set    : in     Word32);

end HW.GFX.GMA.IOSF;
