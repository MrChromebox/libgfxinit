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

with HW.GFX.GMA.Config;
with HW.GFX.GMA.Config_Helpers;
with HW.GFX.GMA.Panel;
with HW.GFX.GMA.PLLs;
with HW.GFX.GMA.DPIO;
with HW.GFX.GMA.SoC.DP;
with HW.GFX.GMA.SoC.HDMI;
with HW.GFX.GMA.SoC.VGA;

with HW.Debug;
with GNAT.Source_Info;

package body HW.GFX.GMA.Connectors
is

   use type SoC.SoC_Port;

   -- The power sequencer and backlight PWM of a panel belong to a pipe.
   Panel_Pipe : constant array (Valid_Panels) of PLLs.DPLL_Pipe :=
     (Panel_1 => Primary,
      Panel_2 => Secondary);

   procedure Post_Reset_Off is null;

   -- A power sequencer only works with a DP port after it locked onto
   -- the port, which needs the port to be enabled once while the DPLL
   -- of the pipe runs. Do it before probing, so we can power up the
   -- panel for the AUX transfers.
   procedure Initialize
   is
      Was_On, Success : Boolean;
   begin
      for Panel in Valid_Panels loop
         declare
            Port : constant Port_Type := Config.Panel_Ports (Panel);
            Pipe : constant PLLs.DPLL_Pipe := Panel_Pipe (Panel);
         begin
            if Port in Active_Port_Type and then
               Config_Helpers.To_Display_Type (Port) = DP and then
               Config_Helpers.To_GPU_Port (Pipe, Port) in SoC.SoC_Port
            then
               declare
                  GPU_Port : constant SoC.SoC_Port :=
                     Config_Helpers.To_GPU_Port (Pipe, Port);
               begin
                  PLLs.On_RBR (Pipe, GPU_Port, Was_On, Success);
                  if Success then
                     SoC.DP.Kick_Power_Sequencer (GPU_Port, Pipe);
                  end if;
                  if not Was_On then
                     PLLs.Off_RBR (Pipe, GPU_Port);
                  end if;
               end;
            end if;
         end;
      end loop;
   end Initialize;

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
         Pipe in DPIO.DPIO_Pipe and
         ((Port_Cfg.Port in SoC.SoC_Port and Port_Cfg.Display in DP | HDMI) or
          (Port_Cfg.Port = VGA and Port_Cfg.Display = VGA));

      if Success and Port_Cfg.Panel in Valid_Panels then
         Success := Pipe = Panel_Pipe (Port_Cfg.Panel);
         pragma Debug (not Success, Debug.Put_Line
           ("ERROR: Panel can't be driven by this pipe."));
      end if;

      if Success and Port_Cfg.Display = VGA then
         -- The DAC doesn't use the PHY and is enabled after the pipe.
         PLLs.On (Pipe, Port_Cfg, Success);
      elsif Success then
         if Port_Cfg.Display = HDMI then
            SoC.HDMI.Prepare (Port_Cfg, Pipe);
         end if;
         DPIO.Pre_PLL_Enable (Port_Cfg.Port);
         PLLs.On (Pipe, Port_Cfg, Success);

         if Success then
            DPIO.Pre_Encoder_Enable (Pipe, Port_Cfg.Port);
            if Port_Cfg.Display = HDMI then
               SoC.HDMI.On (Port_Cfg.Port);
            else
               SoC.DP.Pre_Training (Port_Cfg, Pipe);
               Panel.On (Port_Cfg.Panel, Wait => True);
               SoC.DP.Train (Port_Cfg, Success);
               if not Success then
                  SoC.DP.Off (Port_Cfg.Port);
                  PLLs.Off (Pipe);
               end if;
            end if;
         end if;
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

      if Port_Cfg.Display = VGA then
         SoC.VGA.On (Pipe, Port_Cfg.Mode);
      end if;

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
      elsif Port_Cfg.Display = VGA then
         SoC.VGA.Off;
      end if;
   end Pre_Off;

   procedure Post_Off (Pipe : Pipe_Index; Port_Cfg : Port_Config)
   is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      if Port_Cfg.Port in SoC.SoC_Port then
         if Port_Cfg.Display = HDMI then
            DPIO.Reset_Lanes (Port_Cfg.Port);
         elsif Port_Cfg.Display = DP then
            SoC.DP.Off (Port_Cfg.Port);
         end if;
      end if;

      PLLs.Off (Pipe);
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

      SoC.DP.All_Off;
      SoC.HDMI.All_Off;
      SoC.VGA.Off;
   end Post_All_Off;

end HW.GFX.GMA.Connectors;
