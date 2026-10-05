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

with HW.GFX.GMA.Registers;

with HW.Debug;
with GNAT.Source_Info;

package body HW.GFX.GMA.SoC.VGA
is

   ADPA_DAC_ENABLE         : constant := 1 * 2 ** 31;
   ADPA_USE_VGA_HVPOLARITY : constant := 1 * 2 ** 15;
   ADPA_HSYNC_CNTL_DISABLE : constant := 1 * 2 ** 11;
   ADPA_VSYNC_CNTL_DISABLE : constant := 1 * 2 ** 10;
   ADPA_VSYNC_ACTIVE_HIGH  : constant := 1 * 2 **  4;
   ADPA_HSYNC_ACTIVE_HIGH  : constant := 1 * 2 **  3;

   ADPA_MASK : constant Word32 :=
      PORT_PIPE_SELECT_MASK   or
      ADPA_DAC_ENABLE         or
      ADPA_USE_VGA_HVPOLARITY or
      ADPA_HSYNC_CNTL_DISABLE or
      ADPA_VSYNC_CNTL_DISABLE or
      ADPA_VSYNC_ACTIVE_HIGH  or
      ADPA_HSYNC_ACTIVE_HIGH;

   ----------------------------------------------------------------------------

   procedure Detect (Present : out Boolean)
   is
      ADPA : Word32;
   begin
      Registers.Read (Registers.GMCH_ADPA, ADPA);
      Present := (ADPA and ADPA_DAC_ENABLE) /= 0;
      if not Present then
         Registers.Write
           (Register => Registers.GMCH_ADPA,
            Value    => ADPA or ADPA_DAC_ENABLE or
                        ADPA_HSYNC_CNTL_DISABLE or ADPA_VSYNC_CNTL_DISABLE);
         Registers.Is_Set_Mask
           (Register => Registers.GMCH_ADPA,
            Mask     => ADPA_DAC_ENABLE,
            Result   => Present);
         Registers.Write (Registers.GMCH_ADPA, ADPA);
      end if;
   end Detect;

   ----------------------------------------------------------------------------

   procedure On
     (Pipe : in Pipe_Index;
      Mode : in Mode_Type)
   is
      Polarity : constant Word32 :=
        (if Mode.H_Sync_Active_High then ADPA_HSYNC_ACTIVE_HIGH else 0) or
        (if Mode.V_Sync_Active_High then ADPA_VSYNC_ACTIVE_HIGH else 0);
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Registers.Unset_And_Set_Mask
        (Register   => Registers.GMCH_ADPA,
         Mask_Unset => ADPA_MASK,
         Mask_Set   => ADPA_DAC_ENABLE or
                       PORT_PIPE_SELECT (Pipe) or
                       Polarity);
      Registers.Posting_Read (Registers.GMCH_ADPA);
   end On;

   procedure Off
   is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Registers.Unset_And_Set_Mask
        (Register   => Registers.GMCH_ADPA,
         Mask_Unset => ADPA_DAC_ENABLE,
         Mask_Set   => ADPA_HSYNC_CNTL_DISABLE or
                       ADPA_VSYNC_CNTL_DISABLE);
      Registers.Posting_Read (Registers.GMCH_ADPA);
   end Off;

end HW.GFX.GMA.SoC.VGA;
