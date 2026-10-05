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
with HW.GFX.GMA.Config_Helpers;
with HW.GFX.GMA.Registers;
with HW.GFX.GMA.SoC.VGA;

package body HW.GFX.GMA.Port_Detect
is

   PORT_DETECTED                    : constant := 1 * 2 **  2;

   PORTB_HOTPLUG_INT_EN             : constant := 1 * 2 ** 29;
   PORTC_HOTPLUG_INT_EN             : constant := 1 * 2 ** 28;
   PORTD_HOTPLUG_INT_EN             : constant := 1 * 2 ** 27;
   CRT_HOTPLUG_INT_EN               : constant := 1 * 2 **  9;
   CRT_HOTPLUG_VOLTAGE_COMPARE_50   : constant := 1 * 2 **  5;

   -- Port D is only available on Braswell.
   subtype VLV_Port is GPU_Port range DIGI_B .. DIGI_D;

   PORT_HOTPLUG_INT_EN : constant array (VLV_Port) of Word32 :=
     (DIGI_B => PORTB_HOTPLUG_INT_EN,
      DIGI_C => PORTC_HOTPLUG_INT_EN,
      DIGI_D => PORTD_HOTPLUG_INT_EN);

   type Port_Regs is array (VLV_Port) of Registers.Registers_Index;
   HDMI_CTL : constant Port_Regs :=
     (DIGI_B => Registers.GMCH_HDMIB,
      DIGI_C => Registers.GMCH_HDMIC,
      DIGI_D => Registers.CHV_HDMID);
   DP_CTL : constant Port_Regs :=
     (DIGI_B => Registers.GMCH_DP_B,
      DIGI_C => Registers.GMCH_DP_C,
      DIGI_D => Registers.GMCH_DP_D);

   HOTPLUG_INT_STATUS : constant array (Active_Port_Type) of Word32 :=
     (DP1 | HDMI1 => 3 * 2 ** 17,
      DP2 | HDMI2 => 3 * 2 ** 19,
      DP3 | HDMI3 => 3 * 2 ** 21,
      Analog      => 1 * 2 ** 11,
      others      => 0);

   procedure Initialize
   is
      To_HDMI_Port : constant array (VLV_Port) of Port_Type :=
        (DIGI_B => HDMI1,
         DIGI_C => HDMI2,
         DIGI_D => HDMI3);
      To_DP_Port : constant array (VLV_Port) of Port_Type :=
        (DIGI_B => DP1,
         DIGI_C => DP2,
         DIGI_D => DP3);
      Last_Port : constant VLV_Port :=
        (if Config.Has_CHV_PHY then DIGI_D else DIGI_C);

      HDMI_Detected, DP_Detected, Is_Panel, DAC_Present : Boolean;
      Hotplug_Enable : Word32 := 0;
   begin
      Config.Valid_Port := (others => False);

      SoC.VGA.Detect (DAC_Present);
      Config.Valid_Port (Analog) := DAC_Present;
      if DAC_Present then
         Hotplug_Enable :=
            CRT_HOTPLUG_INT_EN or CRT_HOTPLUG_VOLTAGE_COMPARE_50;
      end if;

      for Port in VLV_Port range VLV_Port'First .. Last_Port loop
         Registers.Is_Set_Mask
           (Register => HDMI_CTL (Port),
            Mask     => PORT_DETECTED,
            Result   => HDMI_Detected);
         Registers.Is_Set_Mask
           (Register => DP_CTL (Port),
            Mask     => PORT_DETECTED,
            Result   => DP_Detected);

         -- The detect straps latch the DDC data line. As eDP doesn't
         -- use DDC, we have to trust the panel configuration instead.
         Is_Panel := Config_Helpers.To_Panel (To_DP_Port (Port)) /= No_Panel;

         Config.Valid_Port (To_DP_Port (Port)) := DP_Detected or Is_Panel;
         Config.Valid_Port (To_HDMI_Port (Port)) :=
            HDMI_Detected and not Is_Panel;

         -- An enabled internal-panel hotplug interrupt leaves a live status
         -- and a pending event set at handoff. Baytrail Windows then hangs
         -- in suspend.
         if (DP_Detected or HDMI_Detected) and then not Is_Panel then
            Hotplug_Enable := Hotplug_Enable or PORT_HOTPLUG_INT_EN (Port);
         end if;
      end loop;

      Registers.Write
        (Register => Registers.PORT_HOTPLUG_EN,
         Value    => Hotplug_Enable);
   end Initialize;

   procedure Hotplug_Detect (Port : in Active_Port_Type; Detected : out Boolean)
   is
      Ctl32 : Word32;
   begin
      Registers.Read (Register => Registers.PORT_HOTPLUG_STAT,
                      Value    => Ctl32);
      Detected := (Ctl32 and HOTPLUG_INT_STATUS (Port)) /= 0;

      if Detected then
         Registers.Set_Mask
           (Register => Registers.PORT_HOTPLUG_STAT,
            Mask     => HOTPLUG_INT_STATUS (Port));
      end if;
   end Hotplug_Detect;

   procedure Clear_Hotplug_Detect (Port : Active_Port_Type)
   is
      Ignored_HPD : Boolean;
   begin
      pragma Warnings (GNATprove, Off, "unused assignment to ""Ignored_HPD""",
                       Reason => "We want to clear pending events only");
      Port_Detect.Hotplug_Detect (Port, Ignored_HPD);
      pragma Warnings (GNATprove, On, "unused assignment to ""Ignored_HPD""");
   end Clear_Hotplug_Detect;

   procedure Hotplug_Live (Port : in Active_Port_Type; Live : out Boolean)
   is
      pragma Unreferenced (Port);
   begin
      Live := False;
   end Hotplug_Live;

end HW.GFX.GMA.Port_Detect;
