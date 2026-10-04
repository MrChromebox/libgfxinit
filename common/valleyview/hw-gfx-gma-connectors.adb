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

package body HW.GFX.GMA.Connectors
is

   procedure Post_Reset_Off is null;
   procedure Initialize is null;

   procedure Prepare
     (Port     : in     Active_Port_Type;
      Port_Cfg : in out Port_Config;
      Success  :    out Boolean)
   is
   begin
      Success := False;
   end Prepare;

   procedure Pre_On
     (Pipe        : in     Pipe_Index;
      Port_Cfg    : in     Port_Config;
      PLL_Hint    : in     Word32;
      Success     :    out Boolean)
   is
   begin
      Success := False;
   end Pre_On;

   procedure Post_On
     (Pipe     : in     Pipe_Index;
      Port_Cfg : in     Port_Config;
      PLL_Hint : in     Word32;
      Success  :    out Boolean)
   is
   begin
      Success := False;
   end Post_On;

   procedure Pre_Off (Pipe : Pipe_Index; Port_Cfg : Port_Config) is null;
   procedure Post_Off (Pipe : Pipe_Index; Port_Cfg : Port_Config) is null;

   procedure Pre_All_Off is null;
   procedure Post_All_Off is null;

end HW.GFX.GMA.Connectors;
