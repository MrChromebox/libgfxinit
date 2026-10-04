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

with HW.GFX.GMA.Panel;
with HW.GFX.GMA.PLLs;
with HW.GFX.GMA.DPIO;
with HW.GFX.GMA.SoC.HDMI;

with HW.Debug;
with GNAT.Source_Info;

package body HW.GFX.GMA.Connectors
is

   use type SoC.SoC_Port;

   procedure Post_Reset_Off is null;
   procedure Initialize is null;

   ----------------------------------------------------------------------------

   procedure Prepare
     (Port     : in     Active_Port_Type;
      Port_Cfg : in out Port_Config;
      Success  :    out Boolean)
   is
   begin
      Success := True;
   end Prepare;

   ----------------------------------------------------------------------------

   -- The DPLL of the pipe has to be enabled after the PHY preparation
   -- and before the encoder setup, so we enable everything up to the
   -- port here, before the pipe is enabled, like i915 does.
   procedure Pre_On
     (Pipe        : in     Pipe_Index;
      Port_Cfg    : in     Port_Config;
      PLL_Hint    : in     Word32;
      Success     :    out Boolean)
   is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Success :=
         Pipe in PLLs.DPLL_Pipe and
         Port_Cfg.Port in SoC.SoC_Port and
         Port_Cfg.Display = HDMI;

      if Success then
         SoC.HDMI.Prepare (Port_Cfg, Pipe);
         DPIO.Pre_PLL_Enable (Port_Cfg.Port);
         PLLs.On (Pipe, Port_Cfg, Success);
      end if;

      if Success then
         DPIO.Pre_Encoder_Enable (Pipe, Port_Cfg.Port);
         SoC.HDMI.On (Port_Cfg.Port);
      end if;
   end Pre_On;

   procedure Post_On
     (Pipe     : in     Pipe_Index;
      Port_Cfg : in     Port_Config;
      PLL_Hint : in     Word32;
      Success  :    out Boolean)
   is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Panel.On (Port_Cfg.Panel, Wait => False);
      Panel.Backlight_On (Port_Cfg.Panel);

      Success := True;
   end Post_On;

   ----------------------------------------------------------------------------

   procedure Pre_Off (Pipe : Pipe_Index; Port_Cfg : Port_Config)
   is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Panel.Backlight_Off (Port_Cfg.Panel);
      Panel.Off (Port_Cfg.Panel);

      if Port_Cfg.Port in SoC.SoC_Port and Port_Cfg.Display = HDMI then
         SoC.HDMI.Off (Port_Cfg.Port);
      end if;
   end Pre_Off;

   procedure Post_Off (Pipe : Pipe_Index; Port_Cfg : Port_Config)
   is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      if Port_Cfg.Port in SoC.SoC_Port and Port_Cfg.Display = HDMI then
         DPIO.Reset_Lanes (Port_Cfg.Port);
      end if;

      if Pipe in PLLs.DPLL_Pipe then
         PLLs.Off (Pipe);
      end if;
   end Post_Off;

   ----------------------------------------------------------------------------

   procedure Pre_All_Off
   is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      for P in Valid_Panels loop
         Panel.Backlight_Off (P);
         Panel.Off (P);
      end loop;
   end Pre_All_Off;

   procedure Post_All_Off
   is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      SoC.HDMI.All_Off;
   end Post_All_Off;

end HW.GFX.GMA.Connectors;
