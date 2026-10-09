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

with HW.Debug;
with GNAT.Source_Info;

with HW.GFX.DP_Defs;

use type HW.Word8;
use type HW.Word16;

package body HW.GFX.DP_Aux_Backlight is

   EDP_GENERAL_CAP_1                      : constant := 16#00701#;
   EDP_TCON_BACKLIGHT_ADJUSTMENT_CAP      : constant := 1 * 2 ** 0;
   EDP_BACKLIGHT_AUX_ENABLE_CAP           : constant := 1 * 2 ** 2;

   -- EDP_BACKLIGHT_ADJUSTMENT_CAP, read along with EDP_GENERAL_CAP_1
   EDP_BACKLIGHT_BRIGHTNESS_AUX_SET_CAP   : constant := 1 * 2 ** 1;
   EDP_BACKLIGHT_BRIGHTNESS_BYTE_COUNT    : constant := 1 * 2 ** 2;

   EDP_DISPLAY_CONTROL_REGISTER           : constant := 16#00720#;
   EDP_BACKLIGHT_ENABLE                   : constant := 1 * 2 ** 0;

   EDP_BACKLIGHT_MODE_SET_REGISTER        : constant := 16#00721#;
   EDP_BACKLIGHT_CONTROL_MODE_DPCD        : constant := 2 * 2 ** 0;

   EDP_BACKLIGHT_BRIGHTNESS_MSB           : constant := 16#00722#;

   -- followed by EDP_PWMGEN_BIT_COUNT_CAP_MIN and _MAX
   EDP_PWMGEN_BIT_COUNT                   : constant := 16#00724#;
   EDP_PWMGEN_BIT_COUNT_MASK              : constant := 16#1f#;

   type Backlight_Caps is record
      Aux_Enable  : Boolean;
      Two_Bytes   : Boolean;
   end record;

   procedure Read_Caps
     (Port     : in     T;
      Caps     :    out Backlight_Caps;
      Success  :    out Boolean)
   is
      Data : DP_Defs.Aux_Payload;
      Length : DP_Defs.Aux_Payload_Length;
   begin
      Length := 2;
      Aux_Ch.Aux_Read
        (Port     => Port,
         Address  => EDP_GENERAL_CAP_1,
         Length   => Length,
         Data     => Data,
         Success  => Success);
      Success := Success and then Length = 2 and then
                 (Data (0) and EDP_TCON_BACKLIGHT_ADJUSTMENT_CAP) /= 0 and then
                 (Data (1) and EDP_BACKLIGHT_BRIGHTNESS_AUX_SET_CAP) /= 0;

      if Success then
         Caps :=
           (Aux_Enable => (Data (0) and EDP_BACKLIGHT_AUX_ENABLE_CAP) /= 0,
            Two_Bytes  => (Data (1) and EDP_BACKLIGHT_BRIGHTNESS_BYTE_COUNT) /= 0);
      else
         Caps := (Aux_Enable => False, Two_Bytes => False);
      end if;
   end Read_Caps;

   procedure Write_Byte
     (Port     : in     T;
      Address  : in     DP_Defs.Aux_Message_Address;
      Value    : in     Word8;
      Success  :    out Boolean)
   is
   begin
      Aux_Ch.Aux_Write
        (Port     => Port,
         Address  => Address,
         Length   => 1,
         Data     => (0 => Value, others => 0),
         Success  => Success);
   end Write_Byte;

   procedure Set_Enable
     (Port     : in     T;
      Enable   : in     Boolean;
      Success  :    out Boolean)
   is
      Data : DP_Defs.Aux_Payload;
      Length : DP_Defs.Aux_Payload_Length;
   begin
      Length := 1;
      Aux_Ch.Aux_Read
        (Port     => Port,
         Address  => EDP_DISPLAY_CONTROL_REGISTER,
         Length   => Length,
         Data     => Data,
         Success  => Success);
      Success := Success and Length = 1;
      if Success then
         Write_Byte
           (Port     => Port,
            Address  => EDP_DISPLAY_CONTROL_REGISTER,
            Value    =>
              (if Enable
               then Data (0) or EDP_BACKLIGHT_ENABLE
               else Data (0) and not EDP_BACKLIGHT_ENABLE),
            Success  => Success);
      end if;
   end Set_Enable;

   subtype Bit_Count_Range is Positive range 1 .. 16;

   procedure Setup_Bit_Count
     (Port        : in     T;
      Two_Bytes   : in     Boolean;
      Bit_Count   :    out Bit_Count_Range;
      Success     :    out Boolean)
   with
      Post => (if not Two_Bytes then Bit_Count <= 8)
   is
      Data : DP_Defs.Aux_Payload;
      Length : DP_Defs.Aux_Payload_Length;
      Raw_Count, Count_Min, Count_Max : Natural;
      Max_Bits : constant Bit_Count_Range := (if Two_Bytes then 16 else 8);
   begin
      Bit_Count := Max_Bits;

      Length := 3;
      Aux_Ch.Aux_Read
        (Port     => Port,
         Address  => EDP_PWMGEN_BIT_COUNT,
         Length   => Length,
         Data     => Data,
         Success  => Success);
      Success := Success and Length = 3;
      if not Success then
         pragma Debug (Debug.Put_Line ("Failed to read PWMGEN bit count."));
         return;
      end if;

      Raw_Count := Natural (Data (0) and EDP_PWMGEN_BIT_COUNT_MASK);
      Count_Min := Natural (Data (1) and EDP_PWMGEN_BIT_COUNT_MASK);
      Count_Max := Natural (Data (2) and EDP_PWMGEN_BIT_COUNT_MASK);

      -- The sink uses the minimum if the bit count is below it.
      if Raw_Count < Count_Min and Count_Min <= Count_Max then
         Raw_Count := Count_Min;
         Write_Byte
           (Port     => Port,
            Address  => EDP_PWMGEN_BIT_COUNT,
            Value    => Word8 (Raw_Count),
            Success  => Success);
         if not Success then
            pragma Debug (Debug.Put_Line
              ("Failed to write PWMGEN bit count."));
            return;
         end if;
      end if;

      if Raw_Count in 1 .. Max_Bits then
         Bit_Count := Raw_Count;
      end if;
   end Setup_Bit_Count;

   -- Switch the panel to DPCD brightness control at 50% brightness.
   procedure On (Port : in T)
   is
      Caps : Backlight_Caps;
      Bit_Count : Bit_Count_Range;
      Level : Word16;
      Success, Ignored_Success : Boolean;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Read_Caps (Port, Caps, Success);
      if not Success then
         pragma Debug (Debug.Put_Line
           ("Panel doesn't support DPCD brightness control."));
         return;
      end if;

      Setup_Bit_Count (Port, Caps.Two_Bytes, Bit_Count, Success);
      if not Success then
         return;
      end if;

      Level := Shift_Left (1, Bit_Count - 1);

      pragma Debug (Debug.Put ("AUX backlight: bit count "));
      pragma Debug (Debug.Put_Int8 (Int8 (Bit_Count)));
      pragma Debug (Debug.Put (", level "));
      pragma Debug (Debug.Put_Word16 (Level));
      pragma Debug (Debug.New_Line);

      Write_Byte
        (Port     => Port,
         Address  => EDP_BACKLIGHT_MODE_SET_REGISTER,
         Value    => EDP_BACKLIGHT_CONTROL_MODE_DPCD,
         Success  => Success);
      if not Success then
         pragma Debug (Debug.Put_Line ("Failed to set DPCD backlight mode."));
         return;
      end if;

      if Caps.Two_Bytes then
         Aux_Ch.Aux_Write
           (Port     => Port,
            Address  => EDP_BACKLIGHT_BRIGHTNESS_MSB,
            Length   => 2,
            Data     => (0 => Word8 (Shift_Right (Level, 8)),
                         1 => Word8 (Level and 16#ff#),
                         others => 0),
            Success  => Success);
      else
         Write_Byte
           (Port     => Port,
            Address  => EDP_BACKLIGHT_BRIGHTNESS_MSB,
            Value    => Word8 (Level),
            Success  => Success);
      end if;
      if not Success then
         pragma Debug (Debug.Put_Line ("Failed to set backlight level."));
         return;
      end if;

      if Caps.Aux_Enable then
         Set_Enable (Port, True, Ignored_Success);
         pragma Debug (not Ignored_Success, Debug.Put_Line
           ("Failed to enable backlight."));
      end if;
   end On;

   procedure Off (Port : in T)
   is
      Caps : Backlight_Caps;
      Success, Ignored_Success : Boolean;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Read_Caps (Port, Caps, Success);
      if Success and Caps.Aux_Enable then
         Set_Enable (Port, False, Ignored_Success);
         pragma Debug (not Ignored_Success, Debug.Put_Line
           ("Failed to disable backlight."));
      end if;
   end Off;

end HW.GFX.DP_Aux_Backlight;
