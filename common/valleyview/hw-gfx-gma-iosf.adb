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

package body HW.GFX.GMA.IOSF is

   SB_MRD_NP      : constant := 16#00#;
   SB_MWR_NP      : constant := 16#01#;
   SB_CRRDDA_NP   : constant := 16#06#;
   SB_CRWRDA_NP   : constant := 16#07#;

   type Unit_Array is array (Unit_Type) of Word32;
   Port_ID : constant Unit_Array :=
     (CCK   => 16#14#,
      CCU   => 16#a9#,
      PUnit => 16#04#,
      DPIO  => 16#12#);

   -- DPIO uses MMIO style accesses, the others private register ones
   Read_Opcode : constant Unit_Array :=
     (DPIO   => SB_MRD_NP,
      others => SB_CRRDDA_NP);
   Write_Opcode : constant Unit_Array :=
     (DPIO   => SB_MWR_NP,
      others => SB_CRWRDA_NP);

   IOSF_OPCODE_SHIFT       : constant := 16;
   IOSF_PORT_SHIFT         : constant := 8;
   IOSF_BYTE_ENABLES_ALL   : constant := 16#f# * 2 ** 4;
   IOSF_SB_BUSY            : constant := 1 * 2 ** 0;

   IOSF_TIMEOUT_MS         : constant := 10;

   function Request (Unit : Unit_Type; Opcode : Word32) return Word32 is
     (Shift_Left (Opcode, IOSF_OPCODE_SHIFT) or
      Shift_Left (Port_ID (Unit), IOSF_PORT_SHIFT) or
      IOSF_BYTE_ENABLES_ALL or
      IOSF_SB_BUSY);

   ----------------------------------------------------------------------------

   procedure Transaction
     (Unit     : in     Unit_Type;
      Is_Read  : in     Boolean;
      Register : in     Word32;
      Value    : in out Word32;
      Success  :    out Boolean)
   is
   begin
      Registers.Wait_Unset_Mask
        (Register => Registers.VLV_IOSF_DOORBELL_REQ,
         Mask     => IOSF_SB_BUSY,
         TOut_MS  => IOSF_TIMEOUT_MS,
         Success  => Success);
      if not Success then
         return;
      end if;

      Registers.Write (Registers.VLV_IOSF_ADDR, Register, Verbose => False);
      Registers.Write
        (Register => Registers.VLV_IOSF_DATA,
         Value    => (if Is_Read then 0 else Value),
         Verbose  => False);
      Registers.Write
        (Register => Registers.VLV_IOSF_DOORBELL_REQ,
         Value    => Request
           (Unit   => Unit,
            Opcode => (if Is_Read
                       then Read_Opcode (Unit) else Write_Opcode (Unit))),
         Verbose  => False);

      Registers.Wait_Unset_Mask
        (Register => Registers.VLV_IOSF_DOORBELL_REQ,
         Mask     => IOSF_SB_BUSY,
         TOut_MS  => IOSF_TIMEOUT_MS,
         Success  => Success);

      if Is_Read then
         if Success then
            Registers.Read (Registers.VLV_IOSF_DATA, Value, Verbose => False);
         end if;
         Registers.Write (Registers.VLV_IOSF_DATA, 0, Verbose => False);
      end if;
   end Transaction;

   procedure Read
     (Unit     : in     Unit_Type;
      Register : in     Word32;
      Value    :    out Word32)
   is
      Success : Boolean;
   begin
      Value := 16#ffff_ffff#;
      Transaction (Unit, True, Register, Value, Success);

      pragma Debug (Debug.Put (GNAT.Source_Info.Enclosing_Entity & ":  "));
      pragma Debug (Debug.Put_Word32 (Value));
      pragma Debug (Debug.Put (" <- "));
      pragma Debug (Debug.Put_Word16 (Word16 (Register and 16#ffff#)));
      pragma Debug (Debug.Put (":"));
      pragma Debug (Debug.Put (Unit_Type'Image (Unit)));
      pragma Debug (not Success, Debug.Put (" (timed out)"));
      pragma Debug (Debug.New_Line);
   end Read;

   procedure Write
     (Unit     : in     Unit_Type;
      Register : in     Word32;
      Value    : in     Word32)
   is
      Success : Boolean;
      Tmp : Word32 := Value;
   begin
      pragma Debug (Debug.Put (GNAT.Source_Info.Enclosing_Entity & ": "));
      pragma Debug (Debug.Put_Word32 (Value));
      pragma Debug (Debug.Put (" -> "));
      pragma Debug (Debug.Put_Word16 (Word16 (Register and 16#ffff#)));
      pragma Debug (Debug.Put (":"));
      pragma Debug (Debug.Put_Line (Unit_Type'Image (Unit)));

      Transaction (Unit, False, Register, Tmp, Success);

      pragma Debug (not Success, Debug.Put_Line
        (GNAT.Source_Info.Enclosing_Entity & ": timed out"));
   end Write;

   procedure Unset_And_Set_Mask
     (Unit        : in     Unit_Type;
      Register    : in     Word32;
      Mask_Unset  : in     Word32;
      Mask_Set    : in     Word32)
   is
      Value : Word32;
   begin
      Read (Unit, Register, Value);
      Write (Unit, Register, (Value and not Mask_Unset) or Mask_Set);
   end Unset_And_Set_Mask;

end HW.GFX.GMA.IOSF;
