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

with HW.GFX.GMA.Registers;
with HW.GFX.GMA.DPIO;
with HW.GFX.GMA.DPIO_CHV;

with HW.Debug;
with GNAT.Source_Info;

package body HW.GFX.GMA.SoC.HDMI
is

   HDMI_ENABLE                    : constant := 1 * 2 ** 31;
   HDMI_COLOR_FORMAT_8BPC         : constant := 0 * 2 ** 26;
   HDMI_SDVO_ENCODING_HDMI        : constant := 2 * 2 ** 10;
   HDMI_MODE_SELECT_DVI           : constant := 0 * 2 **  9;
   HDMI_MODE_SELECT_HDMI          : constant := 1 * 2 **  9;
   HDMI_VSYNC_ACTIVE_HIGH         : constant := 1 * 2 **  4;
   HDMI_HSYNC_ACTIVE_HIGH         : constant := 1 * 2 **  3;

   type HDMI_Array is array (SoC_Port) of Registers.Registers_Index;
   HDMI_CTL : constant HDMI_Array :=
     (DIGI_B => Registers.GMCH_HDMIB,
      DIGI_C => Registers.GMCH_HDMIC,
      DIGI_D => Registers.CHV_HDMID);

   ----------------------------------------------------------------------------

   procedure Prepare
     (Port_Cfg : in Port_Config;
      Pipe     : in Pipe_Index)
   is
      Polarity : constant Word32 :=
        (if Port_Cfg.Mode.H_Sync_Active_High then
            HDMI_HSYNC_ACTIVE_HIGH else 0) or
        (if Port_Cfg.Mode.V_Sync_Active_High then
            HDMI_VSYNC_ACTIVE_HIGH else 0);
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Registers.Write
        (Register => HDMI_CTL (Port_Cfg.Port),
         Value    => HDMI_PIPE_SELECT (Pipe) or
                     HDMI_SDVO_ENCODING_HDMI or
                     HDMI_COLOR_FORMAT_8BPC or
                     (if Port_Cfg.Mode.HDMI_Sink then
                         HDMI_MODE_SELECT_HDMI else HDMI_MODE_SELECT_DVI) or
                     Polarity);
      Registers.Posting_Read (HDMI_CTL (Port_Cfg.Port));
   end Prepare;

   procedure On (Port : SoC_Port)
   is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      if Config.Has_CHV_PHY then
         DPIO_CHV.Set_HDMI_Signal_Levels (Port);
      elsif Port in DPIO.DPIO_Port then
         DPIO.Set_HDMI_Signal_Levels (Port);
      end if;

      Registers.Set_Mask (HDMI_CTL (Port), HDMI_ENABLE);
      Registers.Posting_Read (HDMI_CTL (Port));

      if Config.Has_CHV_PHY then
         DPIO_CHV.Wait_Port_Ready (Port, Unused_Lanes => 0);
      elsif Port in DPIO.DPIO_Port then
         DPIO.Wait_Port_Ready (Port);
      end if;
   end On;

   ----------------------------------------------------------------------------

   procedure Off (Port : SoC_Port)
   is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Registers.Unset_Mask (HDMI_CTL (Port), HDMI_ENABLE);
      Registers.Posting_Read (HDMI_CTL (Port));
   end Off;

   procedure All_Off
   is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      for Port in SoC_Port range SoC_Port'First .. Last_Port loop
         Off (Port);
      end loop;
   end All_Off;

end HW.GFX.GMA.SoC.HDMI;
